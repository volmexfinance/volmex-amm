// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.11;

import '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/utils/introspection/ERC165StorageUpgradeable.sol';

import './libs/tokens/EIP20NonStandardInterface.sol';
import './libs/tokens/TokenMetadataGenerator.sol';
import './libs/tokens/Token.sol';
import './maths/Math.sol';
import './interfaces/IVolmexRepricer.sol';
import './interfaces/IVolmexProtocol.sol';
import './interfaces/IVolmexPool.sol';
import './interfaces/IFlashLoanReceiver.sol';
import './interfaces/IVolmexController.sol';
import './introspection/ERC165Checker.sol';

/**
 * @title Volmex Pool Contract
 * @author volmex.finance [security@volmexlabs.com]
 */
contract VolmexPool is
    OwnableUpgradeable,
    PausableUpgradeable,
    ERC165StorageUpgradeable,
    Token,
    Math,
    TokenMetadataGenerator
{
    using ERC165Checker for address;
    struct Record {
        uint256 leverage;
        uint256 balance;
    }

    // Used to prevent the re-entry
    bool private _mutex;

    // Address of the pool controller
    address private _controller; // has CONTROL role

    // `finalize` sets `PUBLIC can SWAP`, `PUBLIC can JOIN`
    bool private _finalized;

    // Number of tokens the pool can hold
    uint256 public constant BOUND_TOKENS = 2;
    // Address of the pool tokens
    address[BOUND_TOKENS] private _tokens;
    // This is mapped by token addresses
    mapping(address => Record) internal _records;

    // Value of the current block number while repricing
    uint256 public repricingBlock;
    // Value of upper boundary, set in reference of volatility cap ratio { 250 * 10**18 }
    uint256 public upperBoundary;

    // fee of the pool, used to calculate the swap fee
    uint256 public baseFee;
    // fee on the primary token, used to calculate swap fee, when the swap in asset is primary
    uint256 public feeAmpPrimary;
    // fee on the complement token, used to calculate swap fee, when the swap in asset is complement
    uint256 public feeAmpComplement;
    // Max fee on the swap operation
    uint256 public maxFee;

    // Minimum amount of tokens in the pool
    uint256 public pMin;
    // Minimum amount of token required for swap
    uint256 public qMin;
    // Difference in the primary token amount while swapping with the complement token
    uint256 public exposureLimitPrimary;
    // Difference in the complement token amount while swapping with the primary token
    uint256 public exposureLimitComplement;
    // The amount of collateral required to mint both the volatility tokens
    uint256 private _denomination;

    // Address of the volmex repricer contract
    IVolmexRepricer public repricer;
    // Address of the volmex protocol contract
    IVolmexProtocol public protocol;

    // Number value of the volatility token index at oracle { 0 - ETHV, 1 - BTCV }
    uint256 public volatilityIndex;

    // Interface ID of VolmexRepricer contract
    bytes4 private constant _IVOLMEX_REPRICER_ID = type(IVolmexRepricer).interfaceId;
    // Interface ID of VolmexPool contract
    bytes4 private constant _IVOLMEX_POOL_ID = type(IVolmexPool).interfaceId;
    // Interface ID of VolmexController contract
    bytes4 private constant _IVOLMEX_CONTROLLER_ID = type(IVolmexController).interfaceId;

    uint256 public adminFee;

    uint256 public FLASHLOAN_PREMIUM_TOTAL;

    event LogSwap(
        address indexed caller,
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 tokenAmountIn,
        uint256 tokenAmountOut,
        uint256 fee,
        uint256 tokenBalanceIn,
        uint256 tokenBalanceOut,
        uint256 tokenLeverageIn,
        uint256 tokenLeverageOut
    );

    event LogJoin(address indexed caller, address indexed tokenIn, uint256 tokenAmountIn);

    event LogExit(address indexed caller, address indexed tokenOut, uint256 tokenAmountOut);

    event LogReprice(
        uint256 repricingBlock,
        uint256 balancePrimary,
        uint256 balanceComplement,
        uint256 leveragePrimary,
        uint256 leverageComplement,
        uint256 newLeveragePrimary,
        uint256 newLeverageComplement,
        uint256 estPricePrimary,
        uint256 estPriceComplement
    );

    event LogSetFeeParams(
        uint256 baseFee,
        uint256 maxFee,
        uint256 feeAmpPrimary,
        uint256 feeAmpComplement
    );

    event LogCall(bytes4 indexed sig, address indexed caller, bytes data) anonymous;

    event FlashLoan(
        address indexed target,
        address indexed asset,
        uint256 amount,
        uint256 premium
    );

    event SetController(address indexed controller);

    event UpdatedFlashLoanPremium(uint256 premium);

    /**
     * @notice Used to log the callee's sig, address and data
     */
    modifier logs() {
        emit LogCall(msg.sig, msg.sender, msg.data);
        _;
    }

    /**
     * @notice Used to prevent the re-entry
     */
    modifier lock() {
        require(!_mutex, 'VolmexPool: REENTRY');
        _mutex = true;
        _;
        _mutex = false;
    }

    /**
     * @notice Used to prevent multiple call to view methods
     */
    modifier viewlock() {
        require(!_mutex, 'VolmexPool: REENTRY');
        _;
    }

    /**
     * @notice Used to check the pool is finalised
     */
    modifier onlyFinalized() {
        require(_finalized, 'VolmexPool: Pool is not finalized');
        _;
    }

    /**
     * @notice Used to check the protocol is not settled
     */
    modifier onlyNotSettled() {
        require(!protocol.isSettled(), 'VolmexPool: Protocol is settled');
        _;
    }

    /**
     * @notice Used to check the caller is controller
     */
    modifier onlyController() {
        require(msg.sender == _controller, 'VolmexPool: Caller is not controller');
        _;
    }

    /**
     * @notice Initialize the pool contract with required elements
     *
     * @dev Checks, the protocol is a contract
     * @dev Sets repricer, protocol and controller addresses
     * @dev Sets upperBoundary, volatilityIndex and denomination
     * @dev Make the Pool token name and symbol
     *
     * @param _repricer Address of the volmex repricer contract
     * @param _protocol Address of the volmex protocol contract
     * @param _volatilityIndex Index of the volatility price in oracle
     * @param _baseFee Fee of the pool contract
     * @param _maxFee Max fee of the pool while swap
     * @param _feeAmpPrimary Fee on the primary token
     * @param _feeAmpComplement Fee on the complement token
     *
     * NOTE: The baseFee should be set considering a range not more than 0.02 * 10^18
     */
    function initialize(
        IVolmexRepricer _repricer,
        IVolmexProtocol _protocol,
        uint256 _volatilityIndex,
        uint256 _baseFee,
        uint256 _maxFee,
        uint256 _feeAmpPrimary,
        uint256 _feeAmpComplement
    ) external initializer {
        require(
            _repricer.supportsInterface(_IVOLMEX_REPRICER_ID),
            'VolmexPool: Repricer does not supports interface'
        );
        require(address(_protocol) != address(0), "VolmexPool: protocol address can't be zero");
        __Ownable_init();
        __Pausable_init_unchained(); // Used this, because ownable init is calling context init
        __ERC165Storage_init();
        _registerInterface(_IVOLMEX_POOL_ID);
        repricer = _repricer;

        protocol = _protocol;

        upperBoundary = protocol.volatilityCapRatio() * BONE;

        volatilityIndex = _volatilityIndex;

        _denomination = protocol.volatilityCapRatio();

        adminFee = 30;
        FLASHLOAN_PREMIUM_TOTAL = 9;

        setName(makeTokenName(protocol.volatilityToken().name(), protocol.collateral().name()));
        setSymbol(
            makeTokenSymbol(protocol.volatilityToken().symbol(), protocol.collateral().symbol())
        );

        setFeeParams(_baseFee, _maxFee, _feeAmpPrimary, _feeAmpComplement);
    }

    /**
     * @notice Set controller of the Pool
     *
     * @param __controller Address of the pool contract controller
     */
    function setController(address __controller) external onlyOwner {
        require(
            __controller.supportsInterface(_IVOLMEX_CONTROLLER_ID),
            'VolmexPool: Not Controller'
        );
        _controller = __controller;

        emit SetController(_controller);
    }

    /**
     * @notice Used to update the flash loan premium percent
     */
    function updateFlashLoanPremium(uint256 _premium) external onlyOwner {
        require(_premium > 0 && _premium <= 10000, 'VolmexPool: _premium value not in range');
        FLASHLOAN_PREMIUM_TOTAL = _premium;

        emit UpdatedFlashLoanPremium(FLASHLOAN_PREMIUM_TOTAL);
    }

    /**
     * @notice Used to get flash loan
     *
     * @dev Decrease the token amount from the record before transfer
     * @dev Calculate the premium (fee) on the flash loan
     * @dev Check if executor is valid
     * @dev Increase the token amount of the record after pulling
     */
    function flashLoan(
        address receiverAddress,
        address assetToken,
        uint256 amount,
        bytes calldata params
    ) external lock whenNotPaused onlyController {
        _records[assetToken].balance = _records[assetToken].balance - amount;
        IERC20Modified(assetToken).transfer(receiverAddress, amount);

        IFlashLoanReceiver receiver = IFlashLoanReceiver(receiverAddress);
        uint256 premium = div(mul(amount, FLASHLOAN_PREMIUM_TOTAL), 10000);

        require(
            receiver.executeOperation(assetToken, amount, premium, receiverAddress, params),
            'VolmexPool: Invalid flash loan executor'
        );

        uint256 amountWithPremium = amount + premium;

        IERC20Modified(assetToken).transferFrom(receiverAddress, address(this), amountWithPremium);

        _records[assetToken].balance = _records[assetToken].balance + amountWithPremium;

        emit FlashLoan(receiverAddress, assetToken, amount, premium);
    }

    /**
     * @notice Used to add liquidity to the pool
     *
     * @dev The token amount in of the pool will be calculated and pulled from LP
     *
     * @param poolAmountOut Amount of pool token mint and transfer to LP
     * @param maxAmountsIn Max amount of pool assets an LP can supply
     */
    function joinPool(
        uint256 poolAmountOut,
        uint256[2] calldata maxAmountsIn,
        address receiver
    ) external logs lock onlyFinalized onlyController {
        uint256 poolTotal = totalSupply();
        uint256 ratio = div(poolAmountOut, poolTotal);
        require(ratio != 0, 'VolmexPool: Invalid math approximation');

        for (uint256 i = 0; i < BOUND_TOKENS; i++) {
            address token = _tokens[i];
            uint256 bal = _records[token].balance;
            // This can't be tested, as the div method will fail, due to zero supply of lp token
            // The supply of lp token is greater than zero, means token reserve is greater than zero
            // Also, in the case of swap, there's some amount of tokens available pool more than qMin
            require(bal > 0, 'VolmexPool: Insufficient balance in Pool');
            uint256 tokenAmountIn = mul(ratio, bal);
            require(tokenAmountIn <= maxAmountsIn[i], 'VolmexPool: Amount in limit exploit');
            _records[token].balance = _records[token].balance + tokenAmountIn;
            emit LogJoin(receiver, token, tokenAmountIn);
            _pullUnderlying(token, receiver, tokenAmountIn);
        }

        _mintPoolShare(poolAmountOut);
        _pushPoolShare(receiver, poolAmountOut);
    }

    /**
     * @notice Used to remove liquidity from the pool
     *
     * @dev The token amount out of the pool will be calculated and pushed to LP,
     * and pool token are pulled and burned
     *
     * @param poolAmountIn Amount of pool token transfer to the pool
     * @param minAmountsOut Min amount of pool assets an LP wish to redeem
     */
    function exitPool(
        uint256 poolAmountIn,
        uint256[2] calldata minAmountsOut,
        address receiver
    ) external logs lock onlyFinalized onlyController {
        uint256 poolTotal = totalSupply();
        uint256 ratio = div(poolAmountIn, poolTotal);
        require(ratio != 0, 'VolmexPool: Invalid math approximation');

        for (uint256 i = 0; i < BOUND_TOKENS; i++) {
            address token = _tokens[i];
            uint256 bal = _records[token].balance;
            require(bal > 0, 'VolmexPool: Insufficient balance in Pool');
            uint256 tokenAmountOut = _calculateAmountOut(poolAmountIn, ratio, bal);
            require(tokenAmountOut >= minAmountsOut[i], 'VolmexPool: Amount out limit exploit');
            _records[token].balance = _records[token].balance - tokenAmountOut;
            emit LogExit(receiver, token, tokenAmountOut);
            _pushUnderlying(token, receiver, tokenAmountOut);
        }

        _pullPoolShare(receiver, poolAmountIn);
        _burnPoolShare(poolAmountIn);
    }

    /**
     * @notice Used to swap the pool asset
     *
     * @dev Checks the token address, should be different
     * @dev token amount in should be greater than qMin
     * @dev reprices the assets
     * @dev Calculates the token amount out and spot price
     * @dev Perform swaps
     *
     * @param tokenIn Address of the pool asset which the user supply
     * @param tokenAmountIn Amount of asset the user supply
     * @param tokenOut Address of the pool asset which the user wants
     * @param minAmountOut Minimum amount of asset the user wants
     * @param receiver Address of the contract/user from tokens are pulled
     * @param toController Bool value, if `true` push to controller, else to `receiver`
     */
    function swapExactAmountIn(
        address tokenIn,
        uint256 tokenAmountIn,
        address tokenOut,
        uint256 minAmountOut,
        address receiver,
        bool toController
    )
        external
        logs
        lock
        whenNotPaused
        onlyFinalized
        onlyNotSettled
        onlyController
        returns (uint256 tokenAmountOut, uint256 spotPriceAfter)
    {
        require(tokenIn != tokenOut, 'VolmexPool: Passed same token addresses');
        require(tokenAmountIn >= qMin, 'VolmexPool: Amount in quantity should be larger');

        _reprice();

        Record memory inRecord = _records[tokenIn];
        Record memory outRecord = _records[tokenOut];

        require(
            tokenAmountIn <=
                mul(min(_getLeveragedBalance(inRecord), inRecord.balance), MAX_IN_RATIO),
            'VolmexPool: Amount in max ratio exploit'
        );

        tokenAmountOut = calcOutGivenIn(
            _getLeveragedBalance(inRecord),
            _getLeveragedBalance(outRecord),
            tokenAmountIn,
            0
        );

        uint256 fee = _calcFee(
            inRecord,
            tokenAmountIn,
            outRecord,
            tokenAmountOut,
            _getPrimaryDerivativeAddress() == tokenIn ? feeAmpPrimary : feeAmpComplement
        );

        tokenAmountOut = calcOutGivenIn(
            _getLeveragedBalance(inRecord),
            _getLeveragedBalance(outRecord),
            tokenAmountIn,
            fee
        );
        require(tokenAmountOut >= minAmountOut, 'VolmexPool: Amount out limit exploit');

        uint256 spotPriceBefore = calcSpotPrice(
            _getLeveragedBalance(inRecord),
            _getLeveragedBalance(outRecord),
            0
        );

        spotPriceAfter = _performSwap(
            tokenIn,
            tokenAmountIn,
            tokenOut,
            tokenAmountOut,
            spotPriceBefore,
            fee,
            receiver,
            toController
        );
    }

    /**
     * @notice Used to swap the pool asset
     *
     * @dev Checks the token address, should be different
     * @dev token amount in should be greater than qMin
     * @dev reprices the assets
     * @dev Calculates the token amount out and spot price
     * @dev Perform swaps
     *
     * @param tokenIn Address of the pool asset which the user supply
     * @param maxAmountIn Maximum expected amount of asset the user can supply
     * @param tokenOut Address of the pool asset which the user wants
     * @param tokenAmountOut Amount of asset the user wants
     * @param receiver Address of the contract/user from tokens are pulled
     * @param toController Bool value, if `true` push to controller, else to `receiver`
     */
    function swapExactAmountOut(
        address tokenIn,
        uint256 maxAmountIn,
        address tokenOut,
        uint256 tokenAmountOut,
        address receiver,
        bool toController
    )
        external
        logs
        lock
        whenNotPaused
        onlyFinalized
        onlyNotSettled
        onlyController
        returns (uint256 tokenAmountIn, uint256 spotPriceAfter)
    {
        require(tokenIn != tokenOut, 'VolmexPool: Passed same token addresses');
        require(tokenAmountOut >= qMin, 'VolmexPool: Amount in quantity should be larger');

        _reprice();

        Record memory inRecord = _records[tokenIn];
        Record memory outRecord = _records[tokenOut];

        require(
            tokenAmountOut <=
                mul(min(_getLeveragedBalance(outRecord), outRecord.balance), MAX_OUT_RATIO),
            'VolmexPool: Amount in max ratio exploit'
        );

        tokenAmountIn = calcInGivenOut(
            _getLeveragedBalance(inRecord),
            _getLeveragedBalance(outRecord),
            tokenAmountOut,
            0
        );

        uint256 fee = _calcFee(
            inRecord,
            tokenAmountIn,
            outRecord,
            tokenAmountOut,
            _getPrimaryDerivativeAddress() == tokenIn ? feeAmpPrimary : feeAmpComplement
        );

        tokenAmountIn = calcInGivenOut(
            _getLeveragedBalance(inRecord),
            _getLeveragedBalance(outRecord),
            tokenAmountOut,
            fee
        );
        require(tokenAmountIn <= maxAmountIn, 'VolmexPool: Amount out limit exploit');

        uint256 spotPriceBefore = calcSpotPrice(
            _getLeveragedBalance(inRecord),
            _getLeveragedBalance(outRecord),
            0
        );

        spotPriceAfter = _performSwap(
            tokenIn,
            tokenAmountIn,
            tokenOut,
            tokenAmountOut,
            spotPriceBefore,
            fee,
            receiver,
            toController
        );
    }

    /**
     * @notice Used to finalise the pool with the required attributes and operations
     *
     * @dev Checks, pool is finalised, caller is owner, supplied token balance
     * should be equal
     * @dev Binds the token, and its leverage and balance
     * @dev Calculates the initial pool supply, mints and transfer to the controller
     *
     * @param _primaryBalance Balance amount of primary token
     * @param _primaryLeverage Leverage value of primary token
     * @param _complementBalance  Balance amount of complement token
     * @param _complementLeverage  Leverage value of complement token
     * @param _exposureLimitPrimary Primary to complement swap difference limit
     * @param _exposureLimitComplement Complement to primary swap difference limit
     * @param _pMin Minimum amount of tokens in the pool
     * @param _qMin Minimum amount of token required for swap
     */
    function finalize(
        uint256 _primaryBalance,
        uint256 _primaryLeverage,
        uint256 _complementBalance,
        uint256 _complementLeverage,
        uint256 _exposureLimitPrimary,
        uint256 _exposureLimitComplement,
        uint256 _pMin,
        uint256 _qMin
    ) external logs lock onlyNotSettled onlyOwner {
        require(!_finalized, 'VolmexPool: Pool is finalized');

        require(
            _primaryBalance == _complementBalance,
            'VolmexPool: Assets balance should be same'
        );

        require(baseFee > 0, 'VolmexPool: baseFee should be larger than 0');

        pMin = _pMin;
        qMin = _qMin;
        exposureLimitPrimary = _exposureLimitPrimary;
        exposureLimitComplement = _exposureLimitComplement;

        _finalized = true;

        _bind(0, address(protocol.volatilityToken()), _primaryBalance, _primaryLeverage);
        _bind(
            1,
            address(protocol.inverseVolatilityToken()),
            _complementBalance,
            _complementLeverage
        );

        uint256 initPoolSupply = getDerivativeDenomination() * _primaryBalance;

        uint256 collateralDecimals = uint256(protocol.collateral().decimals());
        if (collateralDecimals < 18) {
            initPoolSupply = initPoolSupply * (10**(18 - collateralDecimals));
        }

        _mintPoolShare(initPoolSupply);
        _pushPoolShare(msg.sender, initPoolSupply);
    }

    /**
     * @notice getter, used to fetch the token amount out and fee
     *
     * @param _tokenIn Address of the token in
     * @param _tokenAmountIn Amount of in token
     */
    function getTokenAmountOut(address _tokenIn, uint256 _tokenAmountIn)
        external
        view
        returns (uint256 tokenAmountOut, uint256 fee)
    {   
        
        (Record memory inRecord, Record memory outRecord) = _getRepriced(_tokenIn);

        tokenAmountOut = calcOutGivenIn(
            _getLeveragedBalance(inRecord),
            _getLeveragedBalance(outRecord),
            _tokenAmountIn,
            0
        );

        fee = _calcFee(
            inRecord,
            _tokenAmountIn,
            outRecord,
            tokenAmountOut,
            _getPrimaryDerivativeAddress() == _tokenIn ? feeAmpPrimary : feeAmpComplement
        );

        tokenAmountOut = calcOutGivenIn(
            _getLeveragedBalance(inRecord),
            _getLeveragedBalance(outRecord),
            _tokenAmountIn,
            fee
        );
    }

    /**
     * @notice getter, used to fetch the token amount in and fee
     *
     * @param _tokenOut Address of the token out
     * @param _tokenAmountOut Amount of out token
     */
    function getTokenAmountIn(address _tokenOut, uint256 _tokenAmountOut)
        external
        view
        returns (uint256 tokenAmountIn, uint256 fee)
    {
        (Record memory inRecord, Record memory outRecord) = _getRepriced(_tokenOut);

        tokenAmountIn = calcInGivenOut(
            _getLeveragedBalance(inRecord),
            _getLeveragedBalance(outRecord),
            _tokenAmountOut,
            0
        );

        fee = _calcFee(
            inRecord,
            _tokenAmountOut,
            outRecord,
            tokenAmountIn,
            _getPrimaryDerivativeAddress() == _tokenOut ? feeAmpPrimary : feeAmpComplement
        );

        tokenAmountIn = calcInGivenOut(
            _getLeveragedBalance(inRecord),
            _getLeveragedBalance(outRecord),
            _tokenAmountOut,
            fee
        );
    }

    function getTokensToJoin(uint256 poolAmountOut)
        external
        view
        returns (uint256[2] memory maxAmountsIn)
    {
        uint256 poolTotal = totalSupply();
        uint256 ratio = div(poolAmountOut, poolTotal);
        require(ratio != 0, 'VolmexPool: Invalid math approximation');
        for (uint256 i = 0; i < BOUND_TOKENS; i++) {
            uint256 bal = _records[_tokens[i]].balance;
            maxAmountsIn[i] = mul(ratio, bal);
        }
    }

    function getTokensToExit(uint256 poolAmountIn)
        external
        view
        returns (uint256[2] memory minAmountsOut)
    {
        uint256 poolTotal = totalSupply();
        uint256 ratio = div(poolAmountIn, poolTotal);
        require(ratio != 0, 'VolmexPool: Invalid math approximation');
        for (uint256 i = 0; i < BOUND_TOKENS; i++) {
            uint256 bal = _records[_tokens[i]].balance;
            minAmountsOut[i] = _calculateAmountOut(poolAmountIn, ratio, bal);
        }
    }

    /**
     * @notice Used to pause the contract
     */
    function pause() external onlyController {
        _pause();
    }

    /**
     * @notice Used to unpause the contract, if paused
     */
    function unpause() external onlyController {
        _unpause();
    }

    /**
     * @notice Used to check the pool is finalized
     */
    function isFinalized() external view returns (bool) {
        return _finalized;
    }

    /**
     * @notice Used to get the token addresses
     */
    function getTokens() external view viewlock returns (address[BOUND_TOKENS] memory tokens) {
        return _tokens;
    }

    /**
     * @notice Used to get the leverage of provided token address
     *
     * @param token Address of the token, either primary or complement
     */
    function getLeverage(address token) external view viewlock returns (uint256) {
        return _records[token].leverage;
    }

    /**
     * @notice Used to get the balance of provided token address
     *
     * @param token Address of the token. either primary or complement
     */
    function getBalance(address token) external view viewlock returns (uint256) {
        return _records[token].balance;
    }

    function getPrimaryDerivativeAddress() external view returns (address) {
        return _getPrimaryDerivativeAddress();
    }

    function getComplementDerivativeAddress() external view returns (address) {
        return _getComplementDerivativeAddress();
    }

    /**
     * @notice Sets all type of fees
     *
     * @dev Checks the contract is finalised and caller is controller of the pool
     *
     * @param _baseFee Fee of the pool contract
     * @param _maxFee Max fee of the pool while swap
     * @param _feeAmpPrimary Fee on the primary token
     * @param _feeAmpComplement Fee on the complement token
     */
    function setFeeParams(
        uint256 _baseFee,
        uint256 _maxFee,
        uint256 _feeAmpPrimary,
        uint256 _feeAmpComplement
    ) internal logs lock onlyNotSettled {
        baseFee = _baseFee;
        maxFee = _maxFee;
        feeAmpPrimary = _feeAmpPrimary;
        feeAmpComplement = _feeAmpComplement;

        emit LogSetFeeParams(_baseFee, _maxFee, _feeAmpPrimary, _feeAmpComplement);
    }

    function _getRepriced(address tokenIn)
        internal
        view
        returns (Record memory inRecord, Record memory outRecord)
    {
        Record memory primaryRecord = _records[_getPrimaryDerivativeAddress()];
        Record memory complementRecord = _records[_getComplementDerivativeAddress()];

        (, , uint256 estPrice) = repricer.reprice(volatilityIndex);

        uint256 primaryRecordLeverageBefore = primaryRecord.leverage;
        uint256 complementRecordLeverageBefore = complementRecord.leverage;

        uint256 leveragesMultiplied = mul(
            primaryRecordLeverageBefore,
            complementRecordLeverageBefore
        );

        primaryRecord.leverage = uint256(
            repricer.sqrtWrapped(
                int256(
                    div(
                        mul(leveragesMultiplied, mul(complementRecord.balance, estPrice)),
                        primaryRecord.balance
                    )
                )
            )
        );
        complementRecord.leverage = div(leveragesMultiplied, primaryRecord.leverage);

        inRecord = _getPrimaryDerivativeAddress() == tokenIn ? primaryRecord : complementRecord;
        outRecord = _getComplementDerivativeAddress() == tokenIn
            ? primaryRecord
            : complementRecord;
    }

    /**
     * @notice Used to calculate the leverage of primary and complement token
     *
     * @dev checks if the repricing block is same, returns for true
     * @dev Fetches the est price of primary, complement and averaged
     * @dev Calculates the primary and complement leverage
     */
    function _reprice() internal virtual {
        if (repricingBlock == block.number) return;
        repricingBlock = block.number;

        Record storage primaryRecord = _records[_getPrimaryDerivativeAddress()];
        Record storage complementRecord = _records[_getComplementDerivativeAddress()];

        uint256 estPricePrimary;
        uint256 estPriceComplement;
        uint256 estPrice;
        (estPricePrimary, estPriceComplement, estPrice) = repricer.reprice(volatilityIndex);

        uint256 primaryRecordLeverageBefore = primaryRecord.leverage;
        uint256 complementRecordLeverageBefore = complementRecord.leverage;

        uint256 leveragesMultiplied = mul(
            primaryRecordLeverageBefore,
            complementRecordLeverageBefore
        );

        primaryRecord.leverage = uint256(
            repricer.sqrtWrapped(
                int256(
                    div(
                        mul(leveragesMultiplied, mul(complementRecord.balance, estPrice)),
                        primaryRecord.balance
                    )
                )
            )
        );
        complementRecord.leverage = div(leveragesMultiplied, primaryRecord.leverage);
        emit LogReprice(
            repricingBlock,
            primaryRecord.balance,
            complementRecord.balance,
            primaryRecordLeverageBefore,
            complementRecordLeverageBefore,
            primaryRecord.leverage,
            complementRecord.leverage,
            estPricePrimary,
            estPriceComplement
        );
    }

    function _performSwap(
        address tokenIn,
        uint256 tokenAmountIn,
        address tokenOut,
        uint256 tokenAmountOut,
        uint256 spotPriceBefore,
        uint256 fee,
        address receiver,
        bool toController
    ) internal returns (uint256 spotPriceAfter) {
        Record storage inRecord = _records[tokenIn];
        Record storage outRecord = _records[tokenOut];

        _requireBoundaryConditions(
            inRecord,
            tokenAmountIn,
            outRecord,
            tokenAmountOut,
            _getPrimaryDerivativeAddress() == tokenIn
                ? exposureLimitPrimary
                : exposureLimitComplement
        );

        _updateLeverages(inRecord, tokenAmountIn, outRecord, tokenAmountOut);

        inRecord.balance = inRecord.balance + tokenAmountIn;
        outRecord.balance = outRecord.balance - tokenAmountOut;

        spotPriceAfter = calcSpotPrice(
            _getLeveragedBalance(inRecord),
            _getLeveragedBalance(outRecord),
            0
        );

        // spotPriceAfter will remain larger, becasue after swap, the out token
        // balance will decrease. equation -> leverageBalance(inToken) / leverageBalance(outToken)
        require(spotPriceAfter >= spotPriceBefore, 'VolmexPool: Amount max in ratio exploit');
        // spotPriceBefore will remain smaller, because tokenAmountOut will be smaller than tokenAmountIn
        // because of the fee and oracle price.
        require(
            spotPriceBefore <= div(tokenAmountIn, tokenAmountOut),
            'VolmexPool: Amount in max in ratio exploit other'
        );

        emit LogSwap(
            msg.sender,
            tokenIn,
            tokenOut,
            tokenAmountIn,
            tokenAmountOut,
            fee,
            inRecord.balance,
            outRecord.balance,
            inRecord.leverage,
            outRecord.leverage
        );

        _pullUnderlying(tokenIn, receiver, tokenAmountIn);
        _pushUnderlying(tokenOut, toController ? _controller : receiver, tokenAmountOut);
    }

    function _getLeveragedBalance(Record memory r) internal pure returns (uint256) {
        return mul(r.balance, r.leverage);
    }

    function _requireBoundaryConditions(
        Record storage inToken,
        uint256 tokenAmountIn,
        Record storage outToken,
        uint256 tokenAmountOut,
        uint256 exposureLimit
    ) internal view {
        require(
            _getLeveragedBalance(outToken) - tokenAmountOut > qMin,
            'VolmexPool: Leverage boundary exploit'
        );
        require(
            outToken.balance - tokenAmountOut > qMin,
            'VolmexPool: Non leverage boundary exploit'
        );

        uint256 lowerBound = div(pMin, upperBoundary - pMin);
        uint256 upperBound = div(upperBoundary - pMin, pMin);
        uint256 value = div(
            _getLeveragedBalance(inToken) + tokenAmountIn,
            _getLeveragedBalance(outToken) - tokenAmountOut
        );

        require(lowerBound < value, 'VolmexPool: Lower boundary');
        require(value < upperBound, 'VolmexPool: Upper boundary');

        (uint256 numerator, bool sign) = subSign(
            inToken.balance + tokenAmountIn + tokenAmountOut,
            outToken.balance
        );

        if (!sign) {
            uint256 denominator = (inToken.balance + tokenAmountIn + outToken.balance) -
                tokenAmountOut;

            require(div(numerator, denominator) < exposureLimit, 'VolmexPool: Exposure boundary');
        }
    }

    function _updateLeverages(
        Record storage inToken,
        uint256 tokenAmountIn,
        Record storage outToken,
        uint256 tokenAmountOut
    ) internal {
        outToken.leverage = div(
            _getLeveragedBalance(outToken) - tokenAmountOut,
            outToken.balance - tokenAmountOut
        );
        require(outToken.leverage > 0, 'VolmexPool: Out token leverage can not be zero');

        inToken.leverage = div(
            _getLeveragedBalance(inToken) + tokenAmountIn,
            inToken.balance + tokenAmountIn
        );
        require(inToken.leverage > 0, 'VolmexPool: In token leverage can not be zero');
    }

    /// @dev Similar to EIP20 transfer, except it handles a False result from `transferFrom` and reverts in that case.
    /// This will revert due to insufficient balance or insufficient allowance.
    /// This function returns the actual amount received,
    /// which may be less than `amount` if there is a fee attached to the transfer.
    /// @notice This wrapper safely handles non-standard ERC-20 tokens that do not return a value.
    /// See here: https://medium.com/coinmonks/missing-return-value-bug-at-least-130-tokens-affected-d67bf08521ca
    function _pullUnderlying(
        address erc20,
        address from,
        uint256 amount
    ) internal returns (uint256) {
        uint256 balanceBefore = IERC20(erc20).balanceOf(address(this));
        IVolmexController(_controller).transferAssetToPool(IERC20Modified(erc20), from, amount);

        bool success;
        //solium-disable-next-line security/no-inline-assembly
        assembly {
            switch returndatasize()
            case 0 {
                // This is a non-standard ERC-20
                success := not(0) // set success to true
            }
            case 32 {
                // This is a compliant ERC-20
                returndatacopy(0, 0, 32)
                success := mload(0) // Set `success = returndata` of external call
            }
            default {
                // This is an excessively non-compliant ERC-20, revert.
                revert(0, 0)
            }
        }
        require(success, 'VolmexPool: Token transfer failed');

        // Calculate the amount that was *actually* transferred
        uint256 balanceAfter = IERC20(erc20).balanceOf(address(this));
        require(balanceAfter >= balanceBefore, 'VolmexPool: Token transfer overflow met');
        return balanceAfter - balanceBefore; // underflow already checked above, just subtract
    }

    /// @dev Similar to EIP20 transfer, except it handles a False success from `transfer` and returns an explanatory
    /// error code rather than reverting. If caller has not called checked protocol's balance, this may revert due to
    /// insufficient cash held in this contract. If caller has checked protocol's balance prior to this call, and verified
    /// it is >= amount, this should not revert in normal conditions.
    /// @notice This wrapper safely handles non-standard ERC-20 tokens that do not return a value.
    /// See here: https://medium.com/coinmonks/missing-return-value-bug-at-least-130-tokens-affected-d67bf08521ca
    function _pushUnderlying(
        address erc20,
        address to,
        uint256 amount
    ) internal {
        EIP20NonStandardInterface(erc20).transfer(to, amount);

        bool success;
        //solium-disable-next-line security/no-inline-assembly
        assembly {
            switch returndatasize()
            case 0 {
                // This is a non-standard ERC-20
                success := not(0) // set success to true
            }
            case 32 {
                // This is a complaint ERC-20
                returndatacopy(0, 0, 32)
                success := mload(0) // Set `success = returndata` of external call
            }
            default {
                // This is an excessively non-compliant ERC-20, revert.
                revert(0, 0)
            }
        }
        require(success, 'VolmexPool: Token out transfer failed');
    }

    /**
     * @notice Used to bind the token, and its leverage and balance
     *
     * @dev This method will transfer the provided assets balance to pool from controller
     */
    function _bind(
        uint256 index,
        address token,
        uint256 balance,
        uint256 leverage
    ) internal {
        require(balance >= qMin, 'VolmexPool: Unsatisfied min balance supplied');
        require(leverage > 0, 'VolmexPool: Token leverage should be greater than 0');

        _records[token] = Record({ leverage: leverage, balance: balance });

        _tokens[index] = token;

        _pullUnderlying(token, msg.sender, balance);
    }

    function _spow3(int256 _value) internal pure returns (int256) {
        return (((_value * _value) / iBONE) * _value) / iBONE;
    }

    function _calcExpEndFee(
        int256[3] memory _inRecord,
        int256[3] memory _outRecord,
        int256 _baseFee,
        int256 _feeAmp,
        int256 _expEnd
    ) internal pure returns (int256) {
        int256 inBalanceLeveraged = _getLeveragedBalanceOfFee(_inRecord[0], _inRecord[1]);
        int256 tokenAmountIn1 = (inBalanceLeveraged * (_outRecord[0] - _inRecord[0])) /
            (inBalanceLeveraged + _getLeveragedBalanceOfFee(_outRecord[0], _outRecord[1]));

        int256 inBalanceLeveragedChanged = inBalanceLeveraged + _inRecord[2] * iBONE;
        int256 tokenAmountIn2 = (inBalanceLeveragedChanged *
            (_inRecord[0] - _outRecord[0] + _inRecord[2] + _outRecord[2])) /
            (inBalanceLeveragedChanged +
                _getLeveragedBalanceOfFee(_outRecord[0], _outRecord[1]) -
                _outRecord[2] *
                iBONE);

        return
            (tokenAmountIn1 *
                _baseFee +
                tokenAmountIn2 *
                (_baseFee + (_feeAmp * ((_expEnd * _expEnd) / iBONE)) / 3)) /
            (tokenAmountIn1 + tokenAmountIn2);
    }

    function _getLeveragedBalanceOfFee(int256 _balance, int256 _leverage)
        internal
        pure
        returns (int256)
    {
        return _balance * _leverage;
    }

    function _calc(
        int256[3] memory _inRecord,
        int256[3] memory _outRecord,
        int256 _baseFee,
        int256 _feeAmp,
        int256 _maxFee
    ) internal pure returns (int256 fee, int256 expStart) {
        expStart = _calcExpStart(_inRecord[0], _outRecord[0]);

        int256 _expEnd = ((_inRecord[0] - _outRecord[0] + _inRecord[2] + _outRecord[2]) * iBONE) /
            (_inRecord[0] + _outRecord[0] + _inRecord[2] - _outRecord[2]);

        if (expStart >= 0) {
            fee =
                _baseFee +
                (_feeAmp * (_spow3(_expEnd) - _spow3(expStart))) /
                (3 * (_expEnd - expStart));
        } else if (_expEnd <= 0) {
            fee = _baseFee;
        } else {
            fee = _calcExpEndFee(_inRecord, _outRecord, _baseFee, _feeAmp, _expEnd);
        }

        if (_maxFee < fee) {
            fee = _maxFee;
        }

        if (iBONE / 1000 > fee) {
            fee = iBONE / 1000;
        }
    }

    function _calcFee(
        Record memory inRecord,
        uint256 tokenAmountIn,
        Record memory outRecord,
        uint256 tokenAmountOut,
        uint256 feeAmp
    ) internal view returns (uint256 fee) {
        int256 ifee;
        (ifee, ) = _calc(
            [int256(inRecord.balance), int256(inRecord.leverage), int256(tokenAmountIn)],
            [int256(outRecord.balance), int256(outRecord.leverage), int256(tokenAmountOut)],
            int256(baseFee),
            int256(feeAmp),
            int256(maxFee)
        );
        require(ifee > 0, 'VolmexPool: Fee should be greater than 0');
        fee = uint256(ifee);
    }

    function _calcExpStart(int256 _inBalance, int256 _outBalance) internal pure returns (int256) {
        return ((_inBalance - _outBalance) * iBONE) / (_inBalance + _outBalance);
    }

    /**
     * @notice Used to calculate the out amount after fee deduction
     */
    function _calculateAmountOut(
        uint256 _poolAmountIn,
        uint256 _ratio,
        uint256 _tokenReserve
    ) internal view returns (uint256 amountOut) {
        uint256 tokenAmount = mul(div(_poolAmountIn, upperBoundary), BONE);
        amountOut = mul(_ratio, _tokenReserve);
        if (amountOut > tokenAmount) {
            uint256 feeAmount = div(mul(tokenAmount, adminFee), 10000);
            amountOut = amountOut - feeAmount;
        }
    }

    function getDerivativeDenomination() internal view returns (uint256) {
        return _denomination;
    }

    function _getPrimaryDerivativeAddress() internal view returns (address) {
        return _tokens[0];
    }

    function _getComplementDerivativeAddress() internal view returns (address) {
        return _tokens[1];
    }

    // ==
    // 'Underlying' token-manipulation functions make external calls but are NOT locked
    // You must `lock` or otherwise ensure reentry-safety

    function _pullPoolShare(address from, uint256 amount) internal {
        _pull(from, amount);
    }

    function _pushPoolShare(address to, uint256 amount) internal {
        _push(to, amount);
    }

    function _mintPoolShare(uint256 amount) internal {
        _mint(amount);
    }

    function _burnPoolShare(uint256 amount) internal {
        _burn(amount);
    }
}

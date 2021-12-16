// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.10

import '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/utils/introspection/ERC165CheckerUpgradeable.sol';

import './libs/tokens/EIP20NonStandardInterface.sol';
import './libs/tokens/TokenMetadataGenerator.sol';
import './libs/tokens/Token.sol';
import './maths/Math.sol';
import './interfaces/IVolmexRepricer.sol';
import './interfaces/IVolmexProtocol.sol';
import './interfaces/IVolmexAMM.sol';
import './interfaces/IFlashLoanReceiver.sol';
import './interfaces/IVolmexController.sol';

/**
 * @title Volmex AMM Contract
 * @author volmex.finance [security@volmexlabs.com]
 */
contract VolmexAMM is
    OwnableUpgradeable,
    PausableUpgradeable,
    Token,
    Math,
    TokenMetadataGenerator
{
    event LOG_SWAP(
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

    event LOG_JOIN(address indexed caller, address indexed tokenIn, uint256 tokenAmountIn);

    event LOG_EXIT(address indexed caller, address indexed tokenOut, uint256 tokenAmountOut);

    event LOG_REPRICE(
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

    event LOG_SET_FEE_PARAMS(
        uint256 baseFee,
        uint256 maxFee,
        uint256 feeAmpPrimary,
        uint256 feeAmpComplement
    ); // TODO: Understand what is Amp here.

    event LOG_CALL(bytes4 indexed sig, address indexed caller, bytes data) anonymous;

    event FlashLoan(
        address indexed target,
        address indexed asset,
        uint256 amount,
        uint256 premium
    );

    event SetController(address indexed controller);

    event UpdatedFlashLoanPremium(uint256 premium);

    struct Record {
        uint256 leverage;
        uint256 balance;
    }

    // Used to prevent the re-entry
    bool private _mutex;

    // Address of the pool controller
    address private controller; // has CONTROL role

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

    // TODO: Understand the pMin
    uint256 public pMin;
    uint256 public qMin;
    // TODO: Need to understand exposureLimitPrimary
    uint256 public exposureLimitPrimary;
    // TODO: Need to understand exposureLimitComplement
    uint256 public exposureLimitComplement;
    // The amount of collateral required to mint both the volatility tokens
    uint256 private denomination;

    // Currently not is use. Required in x5Repricer and callOption
    // TODO: Need to understand the use of these args in repricer
    // uint256 public repricerParam1;
    // uint256 public repricerParam2;

    // Address of the volmex repricer contract
    IVolmexRepricer public repricer;
    // Address of the volmex protocol contract
    IVolmexProtocol public protocol;

    // Number value of the volatility token index at oracle { 0 - ETHV, 1 - BTCV }
    uint256 public volatilityIndex;

    bytes4 private constant _INTERFACE_ID_ERC165 = 0x01ffc9a7;

    uint256 public adminFee;

    uint256 public FLASHLOAN_PREMIUM_TOTAL;

    /**
     * @notice Used to log the callee's sig, address and data
     */
    modifier _logs_() {
        emit LOG_CALL(msg.sig, msg.sender, msg.data);
        _;
    }

    /**
     * @notice Used to prevent the re-entry
     */
    modifier _lock_() {
        require(!_mutex, 'VolmexAMM: REENTRY');
        _mutex = true;
        _;
        _mutex = false;
    }

    /**
     * @notice Used to prevent multiple call to view methods
     */
    modifier _viewlock_() {
        require(!_mutex, 'VolmexAMM: REENTRY');
        _;
    }

    /**
     * @notice Used to check the pool is finalised
     */
    modifier onlyFinalized() {
        require(_finalized, 'VolmexAMM: AMM is not finalized');
        _;
    }

    /**
     * @notice Used to check the protocol is not settled
     */
    modifier onlyNotSettled() {
        require(!protocol.isSettled(), 'VolmexAMM: Protocol is settled');
        _;
    }

    /**
     * @notice Used to check the caller is controller
     */
    modifier onlyController() {
        require(msg.sender == controller, 'VolmexAMM: Caller is not controller');
        _;
    }

    /**
     * @notice Initialize the pool contract with required elements
     *
     * @dev Checks, the protocol is a contract
     * @dev Sets repricer, protocol and controller addresses
     * @dev Sets upperBoundary, volatilityIndex and denomination
     * @dev Make the AMM token name and symbol
     *
     * @param _repricer Address of the volmex repricer contract
     * @param _protocol Address of the volmex protocol contract
     * @param _volatilityIndex Index of the volatility price in oracle
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
            ERC165CheckerUpgradeable.supportsInterface(address(_repricer), _INTERFACE_ID_ERC165),
            'VolmexAMM: Repricer does not supports interface'
        );
        repricer = _repricer;

        // NOTE: Intentionally skipped require check for protocol
        protocol = _protocol;

        __Ownable_init();
        __Pausable_init_unchained();

        upperBoundary = protocol.volatilityCapRatio() * BONE;

        volatilityIndex = _volatilityIndex;

        denomination = protocol.volatilityCapRatio();

        adminFee = 30;
        FLASHLOAN_PREMIUM_TOTAL = 9;

        setName(makeTokenName(protocol.volatilityToken().name(), protocol.collateral().name()));
        setSymbol(
            makeTokenSymbol(protocol.volatilityToken().symbol(), protocol.collateral().symbol())
        );

        setFeeParams(_baseFee, _maxFee, _feeAmpPrimary, _feeAmpComplement);
    }

    /**
     * @notice Set controller of the AMM
     *
     * @param _controller Address of the pool contract controller
     */
    function setController(address _controller) external onlyOwner {
        require(_controller != address(0), 'VolmexAMM: Deployer can not be zero address');
        controller = _controller;

        emit SetController(controller);
    }

    /**
     * @notice Used to update the flash loan premium percent
     */
    function updateFlashLoanPremium(uint256 _premium) external onlyOwner {
        require(_premium > 0 && _premium <= 10000, 'VolmexAMM: _premium value not in range');
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
    ) external _lock_ whenNotPaused onlyController {
        _records[assetToken].balance = sub(_records[assetToken].balance, amount);
        IERC20Modified(assetToken).transfer(receiverAddress, amount);

        IFlashLoanReceiver receiver = IFlashLoanReceiver(receiverAddress);
        uint256 premium = div(mul(amount, FLASHLOAN_PREMIUM_TOTAL), 10000);

        require(
            receiver.executeOperation(assetToken, amount, premium, receiverAddress, params),
            'VolmexAMM: Invalid flash loan executor'
        );

        uint256 amountWithPremium = add(amount, premium);

        IERC20Modified(assetToken).transferFrom(receiverAddress, address(this), amountWithPremium);

        _records[assetToken].balance = add(_records[assetToken].balance, amountWithPremium);

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
    ) external _logs_ _lock_ onlyFinalized onlyController {
        uint256 poolTotal = totalSupply();
        uint256 ratio = div(poolAmountOut, poolTotal);
        require(ratio != 0, 'VolmexAMM: Invalid math approximation');

        for (uint256 i = 0; i < BOUND_TOKENS; i++) {
            address token = _tokens[i];
            uint256 bal = _records[token].balance;
            // This can't be tested, as the div method will fail, due to zero supply of lp token
            // The supply of lp token is greater than zero, means token reserve is greater than zero
            // Also, in the case of swap, there's some amount of tokens available pool more than qMin
            require(bal > 0, 'VolmexAMM: Insufficient balance in AMM');
            uint256 tokenAmountIn = mul(ratio, bal);
            require(tokenAmountIn <= maxAmountsIn[i], 'VolmexAMM: Amount in limit exploit');
            _records[token].balance = add(_records[token].balance, tokenAmountIn);
            emit LOG_JOIN(receiver, token, tokenAmountIn);
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
    ) external _logs_ _lock_ onlyFinalized onlyController {
        uint256 poolTotal = totalSupply();
        uint256 ratio = div(poolAmountIn, poolTotal);
        require(ratio != 0, 'VolmexAMM: Invalid math approximation');

        for (uint256 i = 0; i < BOUND_TOKENS; i++) {
            address token = _tokens[i];
            uint256 bal = _records[token].balance;
            require(bal > 0, 'VolmexAMM: Insufficient balance in AMM');
            uint256 tokenAmountOut = calculateAmountOut(poolAmountIn, ratio, bal);
            require(tokenAmountOut >= minAmountsOut[i], 'VolmexAMM: Amount out limit exploit');
            _records[token].balance = sub(_records[token].balance, tokenAmountOut);
            emit LOG_EXIT(receiver, token, tokenAmountOut);
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
     */
    function swapExactAmountIn(
        address tokenIn,
        uint256 tokenAmountIn,
        address tokenOut,
        uint256 minAmountOut,
        address receiver
    )
        external
        _logs_
        _lock_
        whenNotPaused
        onlyFinalized
        onlyNotSettled
        onlyController
        returns (uint256 tokenAmountOut, uint256 spotPriceAfter)
    {
        require(tokenIn != tokenOut, 'VolmexAMM: Passed same token addresses');
        require(tokenAmountIn >= qMin, 'VolmexAMM: Amount in quantity should be larger');

        _reprice();

        Record memory inRecord = _records[tokenIn];
        Record memory outRecord = _records[tokenOut];

        require(
            tokenAmountIn <=
                mul(min(_getLeveragedBalance(inRecord), inRecord.balance), MAX_IN_RATIO),
            'VolmexAMM: Amount in max ratio exploit'
        );

        tokenAmountOut = calcOutGivenIn(
            _getLeveragedBalance(inRecord),
            _getLeveragedBalance(outRecord),
            tokenAmountIn,
            0
        );

        uint256 fee = calcFee(
            inRecord,
            tokenAmountIn,
            outRecord,
            tokenAmountOut,
            _getPrimaryDerivativeAddress() == tokenIn ? feeAmpPrimary : feeAmpComplement
        );

        uint256 spotPriceBefore = calcSpotPrice(
            _getLeveragedBalance(inRecord),
            _getLeveragedBalance(outRecord),
            0
        );

        tokenAmountOut = calcOutGivenIn(
            _getLeveragedBalance(inRecord),
            _getLeveragedBalance(outRecord),
            tokenAmountIn,
            fee
        );
        require(tokenAmountOut >= minAmountOut, 'VolmexAMM: Amount out limit exploit');

        spotPriceAfter = _performSwap(
            tokenIn,
            tokenAmountIn,
            tokenOut,
            tokenAmountOut,
            spotPriceBefore,
            fee,
            receiver
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
     * @param _exposureLimitPrimary TODO: Need to check this
     * @param _exposureLimitComplement TODO: Need to check this
     * @param _pMin TODO: Need to check this
     * @param _qMin TODO: Need to check this
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
    ) external _logs_ _lock_ onlyNotSettled onlyOwner {
        require(!_finalized, 'VolmexAMM: AMM is finalized');

        require(_primaryBalance == _complementBalance, 'VolmexAMM: Assets balance should be same');

        require(baseFee > 0, 'VolmexAMM: baseFee should be larger than 0');

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
    ) internal _logs_ _lock_ onlyNotSettled {
        baseFee = _baseFee;
        maxFee = _maxFee;
        feeAmpPrimary = _feeAmpPrimary;
        feeAmpComplement = _feeAmpComplement;

        emit LOG_SET_FEE_PARAMS(_baseFee, _maxFee, _feeAmpPrimary, _feeAmpComplement);
    }

    function getRepriced(address tokenIn) internal view returns(Record[2] memory) {
        Record memory primaryRecord = _records[_getPrimaryDerivativeAddress()];
        Record memory complementRecord = _records[_getComplementDerivativeAddress()];

        (,, uint256 estPrice) = repricer.reprice(volatilityIndex);

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
        return [
            _getPrimaryDerivativeAddress() == tokenIn ? primaryRecord : complementRecord,
            _getComplementDerivativeAddress() == tokenIn ? primaryRecord : complementRecord
        ];
    }

    function getTokenAmountOut(
        address tokenIn,
        uint256 tokenAmountIn,
        address tokenOut
    ) external view returns (uint256 tokenAmountOut, uint256 fee) {
        Record memory inRecord = getRepriced(tokenIn)[0];
        Record memory outRecord = getRepriced(tokenIn)[1];

        tokenAmountOut = calcOutGivenIn(
            _getLeveragedBalance(inRecord),
            _getLeveragedBalance(outRecord),
            tokenAmountIn,
            0
        );

        fee = calcFee(
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

        // TODO: Need to lookover the sqrtWrapped equation and calculation
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

        emit LOG_REPRICE(
            repricingBlock,
            primaryRecord.balance,
            complementRecord.balance,
            primaryRecordLeverageBefore,
            complementRecordLeverageBefore,
            primaryRecord.leverage,
            complementRecord.leverage,
            estPricePrimary,
            estPriceComplement
            // underlyingStarts: Value of underlying assets (derivative) in USD in the beginning
            // derivativeVault.underlyingStarts(0)
        );
    }

    function _performSwap(
        address tokenIn,
        uint256 tokenAmountIn,
        address tokenOut,
        uint256 tokenAmountOut,
        uint256 spotPriceBefore,
        uint256 fee,
        address receiver
    ) internal returns (uint256 spotPriceAfter) {
        Record storage inRecord = _records[tokenIn];
        Record storage outRecord = _records[tokenOut];

        // TODO: Need to understand this and it's sub/used method
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

        inRecord.balance = add(inRecord.balance, tokenAmountIn);
        outRecord.balance = sub(outRecord.balance, tokenAmountOut);

        spotPriceAfter = calcSpotPrice(
            _getLeveragedBalance(inRecord),
            _getLeveragedBalance(outRecord),
            0
        );

        // spotPriceAfter will remain larger, becasue after swap, the out token
        // balance will decrease. equation -> leverageBalance(inToken) / leverageBalance(outToken)
        require(spotPriceAfter >= spotPriceBefore, 'VolmexAMM: Amount max in ratio exploit');
        // spotPriceBefore will remain smaller, because tokenAmountOut will be smaller than tokenAmountIn
        // because of the fee and oracle price.
        require(
            spotPriceBefore <= div(tokenAmountIn, tokenAmountOut),
            'VolmexAMM: Amount in max in ratio exploit other'
        );

        emit LOG_SWAP(
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

        address holder = receiver == address(0) ? msg.sender : receiver;
        _pullUnderlying(tokenIn, holder, tokenAmountIn);
        _pushUnderlying(tokenOut, holder, tokenAmountOut);
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
            sub(_getLeveragedBalance(outToken), tokenAmountOut) > qMin,
            'VolmexAMM: Leverage boundary exploit'
        );
        require(
            sub(outToken.balance, tokenAmountOut) > qMin,
            'VolmexAMM: Non leverage boundary exploit'
        );

        uint256 lowerBound = div(pMin, sub(upperBoundary, pMin));
        uint256 upperBound = div(sub(upperBoundary, pMin), pMin);
        uint256 value = div(
            add(_getLeveragedBalance(inToken), tokenAmountIn),
            sub(_getLeveragedBalance(outToken), tokenAmountOut)
        );

        require(lowerBound < value, 'VolmexAMM: Lower boundary');
        require(value < upperBound, 'VolmexAMM: Upper boundary');

        (uint256 numerator, bool sign) = subSign(
            add(add(inToken.balance, tokenAmountIn), tokenAmountOut),
            outToken.balance
        );

        if (!sign) {
            uint256 denominator = sub(
                add(add(inToken.balance, tokenAmountIn), outToken.balance),
                tokenAmountOut
            );

            require(div(numerator, denominator) < exposureLimit, 'VolmexAMM: Exposure boundary');
        }
    }

    function _updateLeverages(
        Record storage inToken,
        uint256 tokenAmountIn,
        Record storage outToken,
        uint256 tokenAmountOut
    ) internal {
        outToken.leverage = div(
            sub(_getLeveragedBalance(outToken), tokenAmountOut),
            sub(outToken.balance, tokenAmountOut)
        );
        require(outToken.leverage > 0, 'VolmexAMM: Out token leverage can not be zero');

        inToken.leverage = div(
            add(_getLeveragedBalance(inToken), tokenAmountIn),
            add(inToken.balance, tokenAmountIn)
        );
        require(inToken.leverage > 0, 'VolmexAMM: In token leverage can not be zero');
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
        IVolmexController(controller).transferAssetToPool(
            IERC20Modified(erc20),
            from,
            amount
        );

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
        require(success, 'VolmexAMM: Token transfer failed');

        // Calculate the amount that was *actually* transferred
        uint256 balanceAfter = IERC20(erc20).balanceOf(address(this));
        require(balanceAfter >= balanceBefore, 'VolmexAMM: Token transfer overflow met');
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
        require(success, 'VolmexAMM: Token out transfer failed');
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
        require(balance >= qMin, 'VolmexAMM: Unsatisfied min balance supplied');
        require(leverage > 0, 'VolmexAMM: Token leverage should be greater than 0');

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

    function calc(
        int256[3] memory _inRecord,
        int256[3] memory _outRecord,
        int256 _baseFee,
        int256 _feeAmp,
        int256 _maxFee
    ) internal pure returns (int256 fee, int256 expStart) {
        expStart = calcExpStart(_inRecord[0], _outRecord[0]);

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

    function calcFee(
        Record memory inRecord,
        uint256 tokenAmountIn,
        Record memory outRecord,
        uint256 tokenAmountOut,
        uint256 feeAmp
    ) internal view returns (uint256 fee) {
        int256 ifee;
        (ifee,) = calc(
            [int256(inRecord.balance), int256(inRecord.leverage), int256(tokenAmountIn)],
            [int256(outRecord.balance), int256(outRecord.leverage), int256(tokenAmountOut)],
            int256(baseFee),
            int256(feeAmp),
            int256(maxFee)
        );
        require(ifee > 0, 'VolmexAMM: Fee should be greater than 0');
        fee = uint256(ifee);
    }

    function calcExpStart(int256 _inBalance, int256 _outBalance) internal pure returns (int256) {
        return ((_inBalance - _outBalance) * iBONE) / (_inBalance + _outBalance);
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) external view virtual returns (bool) {
        return interfaceId == type(IVolmexAMM).interfaceId;
    }

    /**
     * @notice Used to calculate the out amount after fee deduction
     */
    function calculateAmountOut(
        uint256 _poolAmountIn,
        uint256 _ratio,
        uint256 _tokenReserve
    ) internal view returns (uint256 amountOut) {
        uint256 tokenAmount = mul(div(_poolAmountIn, upperBoundary), BONE);
        amountOut = mul(_ratio, _tokenReserve);
        if (amountOut > tokenAmount) {
            uint256 feeAmount = mul(tokenAmount, div(adminFee, 10000));
            amountOut = sub(amountOut, feeAmount);
        }
    }

    /**
     * @notice Used to pause the contract
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Used to unpause the contract, if paused
     */
    function unpause() external onlyOwner {
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
    function getTokens() external view _viewlock_ returns (address[BOUND_TOKENS] memory tokens) {
        return _tokens;
    }

    /**
     * @notice Used to get the leverage of provided token address
     *
     * @param token Address of the token, either primary or complement
     */
    function getLeverage(address token) external view _viewlock_ returns (uint256) {
        return _records[token].leverage;
    }

    /**
     * @notice Used to get the balance of provided token address
     *
     * @param token Address of the token. either primary or complement
     */
    function getBalance(address token) external view _viewlock_ returns (uint256) {
        return _records[token].balance;
    }

    function getPrimaryDerivativeAddress() external view returns (address) {
        return _getPrimaryDerivativeAddress();
    }

    function getComplementDerivativeAddress() external view returns (address) {
        return _getComplementDerivativeAddress();
    }

    function getDerivativeDenomination() internal view returns (uint256) {
        return denomination;
    }

    function _getPrimaryDerivativeAddress() internal view returns (address) {
        return _tokens[0];
    }

    function _getComplementDerivativeAddress() internal view returns (address) {
        return _tokens[1];
    }

    // ==
    // 'Underlying' token-manipulation functions make external calls but are NOT locked
    // You must `_lock_` or otherwise ensure reentry-safety

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

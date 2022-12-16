// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.11;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165StorageUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/introspection/IERC165Upgradeable.sol";

import "./libs/tokens/TokenMetadataGenerator.sol";
import "./libs/tokens/Token.sol";
import "./maths/Math.sol";
import "./interfaces/IEIP20NonStandard.sol";
import "./interfaces/IVolmexRepricer.sol";
import "./interfaces/IVolmexProtocol.sol";
import "./interfaces/IVolmexPool.sol";
import "./interfaces/IVolmexController.sol";

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
    TokenMetadataGenerator,
    IVolmexPool
{
    // Interface ID of VolmexRepricer contract, hashId = 0x822da258
    bytes4 private constant _IVOLMEX_REPRICER_ID = type(IVolmexRepricer).interfaceId;
    // Interface ID of VolmexPool contract, hashId = 0x71e45f88
    bytes4 private constant _IVOLMEX_POOL_ID = type(IVolmexPool).interfaceId;
    // Interface ID of VolmexController contract, hashId = 0xe8f8535b
    bytes4 private constant _IVOLMEX_CONTROLLER_ID = type(IVolmexController).interfaceId;
    // Number of tokens the pool can hold
    uint256 private constant _BOUND_TOKENS = 2;

    // Used to prevent the re-entry
    bool private _mutex;
    // `finalize` sets `PUBLIC can SWAP`, `PUBLIC can JOIN`
    bool public finalized;
    // Address of the pool tokens
    address[_BOUND_TOKENS] public tokens;

    // This is mapped by token addresses
    mapping(address => Record) public records;

    // Address of the pool controller
    IVolmexController public controller;
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
    uint256 public denomination;
    // Address of the volmex repricer contract
    IVolmexRepricer public repricer;
    // Address of the volmex protocol contract
    IVolmexProtocol public protocol;
    // Number value of the volatility token index at oracle { 0 - ETHV, 1 - BTCV }
    uint256 public volatilityIndex;
    // Percentage of fee deducted for admin
    uint256 public adminFee;

    /**
     * @notice Used to log the callee's sig, address and data
     */
    modifier logs() {
        emit Called(msg.sig, msg.sender, msg.data);
        _;
    }

    /**
     * @notice Used to prevent the re-entry
     */
    modifier lock() {
        require(!_mutex, "VolmexPool: REENTRY");
        _mutex = true;
        _;
        _mutex = false;
    }

    /**
     * @notice Used to prevent multiple call to view methods
     */
    modifier viewlock() {
        require(!_mutex, "VolmexPool: REENTRY");
        _;
    }

    /**
     * @notice Used to check the pool is finalised
     */
    modifier onlyFinalized() {
        require(finalized, "VolmexPool: Pool is not finalized");
        _;
    }

    /**
     * @notice Used to check the protocol is not settled
     */
    modifier onlyNotSettled() {
        require(!protocol.isSettled(), "VolmexPool: Protocol is settled");
        _;
    }

    /**
     * @notice Used to check the caller is controller
     */
    modifier onlyController() {
        require(msg.sender == address(controller), "VolmexPool: Caller is not controller");
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
     * NOTE: The baseFee is set 0.02 * 10^18 currently, and it can only be set once. Be cautious
     */
    function initialize(
        IVolmexRepricer _repricer,
        IVolmexProtocol _protocol,
        uint256 _volatilityIndex,
        uint256 _baseFee,
        uint256 _maxFee,
        uint256 _feeAmpPrimary,
        uint256 _feeAmpComplement,
        address _owner
    ) external initializer {
        require(
            IERC165Upgradeable(address(_repricer)).supportsInterface(_IVOLMEX_REPRICER_ID),
            "VolmexPool: Repricer does not supports interface"
        );
        require(address(_protocol) != address(0), "VolmexPool: protocol address can't be zero");

        repricer = _repricer;
        protocol = _protocol;
        upperBoundary = protocol.volatilityCapRatio() * BONE;
        volatilityIndex = _volatilityIndex;
        denomination = protocol.volatilityCapRatio();
        adminFee = 30;
        tokens[0] = address(protocol.volatilityToken());
        tokens[1] = address(protocol.inverseVolatilityToken());

        _setName(_makeTokenName(protocol.volatilityToken().name(), protocol.collateral().name()));
        _setSymbol(
            _makeTokenSymbol(protocol.volatilityToken().symbol(), protocol.collateral().symbol())
        );

        _setFeeParams(_baseFee, _maxFee, _feeAmpPrimary, _feeAmpComplement);

        __Ownable_init();
        __Pausable_init_unchained();
        __ERC165Storage_init();
        _registerInterface(_IVOLMEX_POOL_ID);
        _transferOwnership(_owner);
    }

    /**
     * @notice Set controller of the Pool
     *
     * @param _controller Address of the pool contract controller
     */
    function setController(IVolmexController _controller) external onlyOwner {
        require(
            IERC165Upgradeable(address(_controller)).supportsInterface(_IVOLMEX_CONTROLLER_ID),
            "VolmexPool: Not Controller"
        );
        controller = _controller;

        emit ControllerSet(address(controller));
    }

    /**
     * @notice Used to update the admin fee
     */
    function updateAdminFee(uint256 _fee) external onlyOwner {
        require(_fee <= 10000, "VolmexPool: _fee should be smaller than 10000");
        adminFee = _fee;

        emit AdminFeeUpdated(_fee);
    }

    /**
     * @notice Used to update the volatility index for oracle price tracking
     */
    function updateVolatilityIndex(uint256 _newIndex) external onlyOwner {
        volatilityIndex = _newIndex;

        emit VolatilityIndexUpdated(_newIndex);
    }

    /**
     * @notice Used to set exposure limit
     * @param _exposureLimitPrimary Primary to complement swap difference limit
     * @param _exposureLimitComplement Complement to primary swap difference limit
     */
    function updateExposureLimit(
        uint256 _exposureLimitPrimary,
        uint256 _exposureLimitComplement
    ) external onlyOwner {
        exposureLimitPrimary = _exposureLimitPrimary;
        exposureLimitComplement = _exposureLimitComplement;
        emit ExposureLimitUpdated(exposureLimitPrimary, exposureLimitComplement);
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
        uint256 _qMin,
        address _receiver
    ) external logs lock onlyNotSettled onlyController {
        require(!finalized, "VolmexPool: Pool is finalized");

        require(
            _primaryBalance == _complementBalance,
            "VolmexPool: Assets balance should be same"
        );

        require(baseFee > 0, "VolmexPool: baseFee should be larger than 0");

        pMin = _pMin;
        qMin = _qMin;
        exposureLimitPrimary = _exposureLimitPrimary;
        exposureLimitComplement = _exposureLimitComplement;

        finalized = true;

        _bind(address(protocol.volatilityToken()), _primaryBalance, _primaryLeverage, _receiver);
        _bind(
            address(protocol.inverseVolatilityToken()),
            _complementBalance,
            _complementLeverage,
            _receiver
        );

        uint256 initPoolSupply = denomination * _primaryBalance;

        uint256 collateralDecimals = uint256(protocol.collateral().decimals());
        if (collateralDecimals < 18) {
            initPoolSupply = initPoolSupply * (10**(18 - collateralDecimals));
        }

        _mintPoolShare(initPoolSupply);
        _pushPoolShare(_receiver, initPoolSupply);
    }

    /**
     * @notice Used to add liquidity to the pool
     *
     * @dev The token amount in of the pool will be calculated and pulled from LP
     *
     * @param _poolAmountOut Amount of pool token mint and transfer to LP
     * @param _maxAmountsIn Max amount of pool assets an LP can supply
     */
    function joinPool(
        uint256 _poolAmountOut,
        uint256[2] calldata _maxAmountsIn,
        address _receiver
    ) external logs lock onlyFinalized onlyController {
        uint256 poolTotal = totalSupply();
        uint256 ratio = _div(_poolAmountOut, poolTotal);
        require(ratio != 0, "VolmexPool: Invalid math approximation");

        for (uint256 i = 0; i < _BOUND_TOKENS; i++) {
            address token = tokens[i];
            uint256 bal = records[token].balance;
            // This can't be tested, as the div method will fail, due to zero supply of lp token
            // The supply of lp token is greater than zero, means token reserve is greater than zero
            // Also, in the case of swap, there's some amount of tokens available pool more than qMin
            require(bal > 0, "VolmexPool: Insufficient balance in Pool");
            uint256 tokenAmountIn = _mul(ratio, bal);
            require(tokenAmountIn <= _maxAmountsIn[i], "VolmexPool: Amount in limit exploit");
            records[token].balance = records[token].balance + tokenAmountIn;
            emit Joined(_receiver, token, tokenAmountIn);
            _pullUnderlying(token, _receiver, tokenAmountIn);
        }

        _mintPoolShare(_poolAmountOut);
        _pushPoolShare(_receiver, _poolAmountOut);
    }

    /**
     * @notice Used to remove liquidity from the pool
     *
     * @dev The token amount out of the pool will be calculated and pushed to LP,
     * and pool token are pulled and burned
     *
     * @param _poolAmountIn Amount of pool token transfer to the pool
     * @param _minAmountsOut Min amount of pool assets an LP wish to redeem
     */
    function exitPool(
        uint256 _poolAmountIn,
        uint256[2] calldata _minAmountsOut,
        address _receiver
    ) external logs lock onlyFinalized onlyController {
        uint256 poolTotal = totalSupply();
        uint256 ratio = _div(_poolAmountIn, poolTotal);
        require(ratio != 0, "VolmexPool: Invalid math approximation");

        for (uint256 i = 0; i < _BOUND_TOKENS; i++) {
            address token = tokens[i];
            uint256 bal = records[token].balance;
            require(bal > 0, "VolmexPool: Insufficient balance in Pool");
            (uint256 tokenAmountOut, ) = _calculateAmountOut(
                _poolAmountIn,
                ratio,
                bal,
                upperBoundary,
                adminFee
            );
            require(tokenAmountOut >= _minAmountsOut[i], "VolmexPool: Amount out limit exploit");
            records[token].balance = records[token].balance - tokenAmountOut;
            emit Exited(_receiver, token, tokenAmountOut);
            _pushUnderlying(token, _receiver, tokenAmountOut);
        }

        _pullPoolShare(_receiver, _poolAmountIn);
        _burnPoolShare(_poolAmountIn);
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
     * @param _tokenIn Address of the pool asset which the user supply
     * @param _tokenAmountIn Amount of asset the user supply
     * @param _tokenOut Address of the pool asset which the user wants
     * @param _minAmountOut Minimum amount of asset the user wants
     * @param _receiver Address of the contract/user from tokens are pulled
     * @param _toController Bool value, if `true` push to controller, else to `_receiver`
     */
    function swapExactAmountIn(
        address _tokenIn,
        uint256 _tokenAmountIn,
        address _tokenOut,
        uint256 _minAmountOut,
        address _receiver,
        bool _toController
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
        require(_tokenIn != _tokenOut, "VolmexPool: Passed same token addresses");
        require(_tokenAmountIn >= qMin, "VolmexPool: Amount in quantity should be larger");

        reprice();

        Record memory inRecord = records[_tokenIn];
        Record memory outRecord = records[_tokenOut];

        require(
            _tokenAmountIn <=
                _mul(_min(getLeveragedBalance(inRecord), inRecord.balance), MAX_IN_RATIO),
            "VolmexPool: Amount in max ratio exploit"
        );

        tokenAmountOut = _calcOutGivenIn(
            getLeveragedBalance(inRecord),
            getLeveragedBalance(outRecord),
            _tokenAmountIn,
            0
        );

        uint256 fee = _calcFee(
            inRecord,
            _tokenAmountIn,
            outRecord,
            tokenAmountOut,
            tokens[0] == _tokenIn ? feeAmpPrimary : feeAmpComplement
        );

        tokenAmountOut = _calcOutGivenIn(
            getLeveragedBalance(inRecord),
            getLeveragedBalance(outRecord),
            _tokenAmountIn,
            fee
        );
        require(tokenAmountOut >= _minAmountOut, "VolmexPool: Amount out limit exploit");

        uint256 _spotPriceBefore = calcSpotPrice(
            getLeveragedBalance(inRecord),
            getLeveragedBalance(outRecord),
            0
        );

        spotPriceAfter = _performSwap(
            _tokenIn,
            _tokenAmountIn,
            _tokenOut,
            tokenAmountOut,
            _spotPriceBefore,
            fee,
            _receiver,
            _toController
        );
    }

    /**
     * @notice Used to pause the contract
     *
     * @param _isPause Boolean value to pause or unpause the position token { true = pause, false = unpause }
     */
    function togglePause(bool _isPause) external onlyController {
        _isPause ? _pause() : _unpause();
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
        returns (uint256 minAmountOut, uint256 fee)
    {
        (Record memory inRecord, Record memory outRecord) = _getRepriced(_tokenIn);

        minAmountOut = _calcOutGivenIn(
            getLeveragedBalance(inRecord),
            getLeveragedBalance(outRecord),
            _tokenAmountIn,
            0
        );

        fee = _calcFee(
            inRecord,
            _tokenAmountIn,
            outRecord,
            minAmountOut,
            tokens[0] == _tokenIn ? feeAmpPrimary : feeAmpComplement
        );

        minAmountOut = _calcOutGivenIn(
            getLeveragedBalance(inRecord),
            getLeveragedBalance(outRecord),
            _tokenAmountIn,
            fee
        );
    }

    /**
     * @notice Used to get the leverage of provided token address
     *
     * @param _token Address of the token, either primary or complement
     *
     * Can't remove this method, because struct of this contract can't be fetched in controller contract.
     * We will need to unpack the struct.
     */
    function getLeverage(address _token) external view viewlock returns (uint256) {
        return records[_token].leverage;
    }

    /**
     * @notice Used to get the balance of provided token address
     *
     * @param _token Address of the token. either primary or complement
     */
    function getBalance(address _token) external view viewlock returns (uint256) {
        return records[_token].balance;
    }

    /**
     * @notice Used to calculate the leverage of primary and complement token
     *
     * @dev checks if the repricing block is same, returns for true
     * @dev Fetches the est price of primary, complement and averaged
     * @dev Calculates the primary and complement leverage
     */
    function reprice() public {
        if (repricingBlock == block.number) return;
        repricingBlock = block.number;

        Record storage primaryRecord = records[tokens[0]];
        Record storage complementRecord = records[tokens[1]];

        uint256 estPricePrimary;
        uint256 estPriceComplement;
        uint256 estPrice;
        (estPricePrimary, estPriceComplement, estPrice) = repricer.reprice(volatilityIndex);

        uint256 primaryRecordLeverageBefore = primaryRecord.leverage;
        uint256 complementRecordLeverageBefore = complementRecord.leverage;

        uint256 leveragesMultiplied = _mul(
            primaryRecordLeverageBefore,
            complementRecordLeverageBefore
        );

        primaryRecord.leverage = uint256(
            repricer.sqrtWrapped(
                int256(
                    _div(
                        _mul(leveragesMultiplied, _mul(complementRecord.balance, estPrice)),
                        primaryRecord.balance
                    )
                )
            )
        );
        complementRecord.leverage = _div(leveragesMultiplied, primaryRecord.leverage);
        emit Repriced(
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

    function getLeveragedBalance(Record memory r) public pure returns (uint256) {
        return _mul(r.balance, r.leverage);
    }

    /**
     * @dev Similar to EIP20 transfer, except it handles a False result from `transferFrom` and reverts in that case.
     * This will revert due to insufficient balance or insufficient allowance.
     * This function returns the actual amount received,
     * which may be less than `amount` if there is a fee attached to the transfer.
     * @notice This wrapper safely handles non-standard ERC-20 tokens that do not return a value.
     * See here: https://medium.com/coinmonks/missing-return-value-bug-at-least-130-tokens-affected-d67bf08521ca
     */
    function _pullUnderlying(
        address _erc20,
        address _from,
        uint256 _amount
    ) internal virtual returns (uint256) {
        uint256 balanceBefore = IERC20(_erc20).balanceOf(address(this));
        controller.transferAssetToPool(IERC20Modified(_erc20), _from, _amount);

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
        require(success, "VolmexPool: Token transfer failed");

        // Calculate the amount that was *actually* transferred
        uint256 balanceAfter = IERC20(_erc20).balanceOf(address(this));
        require(balanceAfter >= balanceBefore, "VolmexPool: Token transfer overflow met");
        return balanceAfter - balanceBefore; // underflow already checked above, just subtract
    }

    function _getRepriced(address _tokenIn)
        private
        view
        returns (Record memory inRecord, Record memory outRecord)
    {
        Record memory primaryRecord = records[tokens[0]];
        Record memory complementRecord = records[tokens[1]];

        (, , uint256 estPrice) = repricer.reprice(volatilityIndex);

        uint256 primaryRecordLeverageBefore = primaryRecord.leverage;
        uint256 complementRecordLeverageBefore = complementRecord.leverage;

        uint256 leveragesMultiplied = _mul(
            primaryRecordLeverageBefore,
            complementRecordLeverageBefore
        );

        primaryRecord.leverage = uint256(
            repricer.sqrtWrapped(
                int256(
                    _div(
                        _mul(leveragesMultiplied, _mul(complementRecord.balance, estPrice)),
                        primaryRecord.balance
                    )
                )
            )
        );
        complementRecord.leverage = _div(leveragesMultiplied, primaryRecord.leverage);

        inRecord = tokens[0] == _tokenIn ? primaryRecord : complementRecord;
        outRecord = tokens[1] == _tokenIn ? primaryRecord : complementRecord;
    }

    function _calcFee(
        Record memory _inRecord,
        uint256 _tokenAmountIn,
        Record memory _outRecord,
        uint256 _tokenAmountOut,
        uint256 _feeAmp
    ) private view returns (uint256 fee) {
        int256 ifee;
        (ifee, ) = _calc(
            [int256(_inRecord.balance), int256(_inRecord.leverage), int256(_tokenAmountIn)],
            [int256(_outRecord.balance), int256(_outRecord.leverage), int256(_tokenAmountOut)],
            int256(baseFee),
            int256(_feeAmp),
            int256(maxFee)
        );
        require(ifee > 0, "VolmexPool: Fee should be greater than 0");
        fee = uint256(ifee);
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
    function _setFeeParams(
        uint256 _baseFee,
        uint256 _maxFee,
        uint256 _feeAmpPrimary,
        uint256 _feeAmpComplement
    ) private logs lock onlyNotSettled {
        baseFee = _baseFee;
        maxFee = _maxFee;
        feeAmpPrimary = _feeAmpPrimary;
        feeAmpComplement = _feeAmpComplement;

        emit FeeParamsSet(_baseFee, _maxFee, _feeAmpPrimary, _feeAmpComplement);
    }

    function _performSwap(
        address _tokenIn,
        uint256 _tokenAmountIn,
        address _tokenOut,
        uint256 _tokenAmountOut,
        uint256 _spotPriceBefore,
        uint256 _fee,
        address _receiver,
        bool _toController
    ) private returns (uint256 spotPriceAfter) {
        Record storage inRecord = records[_tokenIn];
        Record storage outRecord = records[_tokenOut];

        _requireBoundaryConditions(
            inRecord,
            _tokenAmountIn,
            outRecord,
            _tokenAmountOut,
            tokens[0] == _tokenIn ? exposureLimitPrimary : exposureLimitComplement
        );

        _updateLeverages(inRecord, _tokenAmountIn, outRecord, _tokenAmountOut);

        inRecord.balance = inRecord.balance + _tokenAmountIn;
        outRecord.balance = outRecord.balance - _tokenAmountOut;

        spotPriceAfter = calcSpotPrice(
            getLeveragedBalance(inRecord),
            getLeveragedBalance(outRecord),
            0
        );

        // spotPriceAfter will remain larger, becasue after swap, the out token
        // balance will decrease. equation -> leverageBalance(_inToken) / leverageBalance(outToken)
        require(spotPriceAfter >= _spotPriceBefore, "VolmexPool: Amount max in ratio exploit");
        // _spotPriceBefore will remain smaller, because _tokenAmountOut will be smaller than _tokenAmountIn
        // because of the fee and oracle price.
        require(
            _spotPriceBefore <= _div(_tokenAmountIn, _tokenAmountOut),
            "VolmexPool: Amount in max in ratio exploit other"
        );

        emit Swapped(
            _tokenIn,
            _tokenOut,
            _tokenAmountIn,
            _tokenAmountOut,
            _fee,
            inRecord.balance,
            outRecord.balance,
            inRecord.leverage,
            outRecord.leverage
        );

        _pullUnderlying(_tokenIn, _receiver, _tokenAmountIn);
        _pushUnderlying(
            _tokenOut,
            _toController ? address(controller) : _receiver,
            _tokenAmountOut
        );
    }

    function _requireBoundaryConditions(
        Record storage _inToken,
        uint256 _tokenAmountIn,
        Record storage _outToken,
        uint256 _tokenAmountOut,
        uint256 _exposureLimit
    ) private view {
        require(
            getLeveragedBalance(_outToken) - _tokenAmountOut > qMin,
            "VolmexPool: Leverage boundary exploit"
        );
        require(
            _outToken.balance - _tokenAmountOut > qMin,
            "VolmexPool: Non leverage boundary exploit"
        );

        uint256 lowerBound = _div(pMin, upperBoundary - pMin);
        uint256 upperBound = _div(upperBoundary - pMin, pMin);
        uint256 value = _div(
            getLeveragedBalance(_inToken) + _tokenAmountIn,
            getLeveragedBalance(_outToken) - _tokenAmountOut
        );

        require(lowerBound < value, "VolmexPool: Lower boundary");
        require(value < upperBound, "VolmexPool: Upper boundary");

        (uint256 numerator, bool sign) = _subSign(
            _inToken.balance + _tokenAmountIn + _tokenAmountOut,
            _outToken.balance
        );

        if (!sign) {
            uint256 denominator = (_inToken.balance + _tokenAmountIn + _outToken.balance) -
                _tokenAmountOut;

            require(
                _div(numerator, denominator) < _exposureLimit,
                "VolmexPool: Exposure boundary"
            );
        }
    }

    function _updateLeverages(
        Record storage _inToken,
        uint256 _tokenAmountIn,
        Record storage _outToken,
        uint256 _tokenAmountOut
    ) private {
        _outToken.leverage = _div(
            getLeveragedBalance(_outToken) - _tokenAmountOut,
            _outToken.balance - _tokenAmountOut
        );
        require(_outToken.leverage > 0, "VolmexPool: Out token leverage can not be zero");

        _inToken.leverage = _div(
            getLeveragedBalance(_inToken) + _tokenAmountIn,
            _inToken.balance + _tokenAmountIn
        );
        require(_inToken.leverage > 0, "VolmexPool: In token leverage can not be zero");
    }

    /**
     * @dev Similar to EIP20 transfer, except it handles a False success from `transfer` and returns an explanatory
     * error code rather than reverting. If caller has not called checked protocol's balance, this may revert due to
     * insufficient cash held in this contract. If caller has checked protocol's balance prior to this call, and verified
     * it is >= amount, this should not revert in normal conditions.
     * @notice This wrapper safely handles non-standard ERC-20 tokens that do not return a value.
     * See here: https://medium.com/coinmonks/missing-return-value-bug-at-least-130-tokens-affected-d67bf08521ca
     */
    function _pushUnderlying(
        address _erc20,
        address _to,
        uint256 _amount
    ) private {
        IEIP20NonStandard(_erc20).transfer(_to, _amount);

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
        require(success, "VolmexPool: Token out transfer failed");
    }

    /**
     * @notice Used to bind the token, and its leverage and balance
     *
     * @dev This method will transfer the provided assets balance to pool from controller
     */
    function _bind(
        address _token,
        uint256 _balance,
        uint256 _leverage,
        address _receiver
    ) private {
        require(_balance >= qMin, "VolmexPool: Unsatisfied min balance supplied");
        require(_leverage > 0, "VolmexPool: Token leverage should be greater than 0");

        records[_token] = Record({ leverage: _leverage, balance: _balance });

        _pullUnderlying(_token, _receiver, _balance);
    }

    // ==
    // 'Underlying' token-manipulation functions make external calls but are NOT locked
    // You must `lock` or otherwise ensure reentry-safety

    function _pullPoolShare(address _from, uint256 _amount) private {
        _pull(_from, _amount);
    }

    function _pushPoolShare(address _to, uint256 _amount) private {
        _push(_to, _amount);
    }

    function _mintPoolShare(uint256 _amount) private {
        _mint(_amount);
    }

    function _burnPoolShare(uint256 _amount) private {
        _burn(_amount);
    }

    function _spow3(int256 _value) private pure returns (int256) {
        return (((_value * _value) / iBONE) * _value) / iBONE;
    }

    function _calcExpEndFee(
        int256[3] memory _inRecord,
        int256[3] memory _outRecord,
        int256 _baseFee,
        int256 _feeAmp,
        int256 _expEnd
    ) private pure returns (int256) {
        int256 inBalanceLeveraged = _inRecord[0] * _inRecord[1];
        int256 tokenAmountIn1 = (inBalanceLeveraged * (_outRecord[0] - _inRecord[0])) /
            (inBalanceLeveraged + (_outRecord[0] * _outRecord[1]));

        int256 inBalanceLeveragedChanged = inBalanceLeveraged + _inRecord[2] * iBONE;
        int256 tokenAmountIn2 = (inBalanceLeveragedChanged *
            (_inRecord[0] - _outRecord[0] + _inRecord[2] + _outRecord[2])) /
            (inBalanceLeveragedChanged + (_outRecord[0] * _outRecord[1]) - _outRecord[2] * iBONE);

        return
            (tokenAmountIn1 *
                _baseFee +
                tokenAmountIn2 *
                (_baseFee + (_feeAmp * ((_expEnd * _expEnd) / iBONE)) / 3)) /
            (tokenAmountIn1 + tokenAmountIn2);
    }

    function _calc(
        int256[3] memory _inRecord,
        int256[3] memory _outRecord,
        int256 _baseFee,
        int256 _feeAmp,
        int256 _maxFee
    ) private pure returns (int256 fee, int256 expStart) {
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

    function _calcExpStart(int256 _inBalance, int256 _outBalance) private pure returns (int256) {
        return ((_inBalance - _outBalance) * iBONE) / (_inBalance + _outBalance);
    }

    uint256[10] private __gap;
}

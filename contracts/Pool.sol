// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.7.6;

import '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/introspection/ERC165CheckerUpgradeable.sol';

import './libs/complifi/tokens/IERC20Metadata.sol';
import './libs/complifi/tokens/EIP20NonStandardInterface.sol';
import './libs/complifi/tokens/TokenMetadataGenerator.sol';
import './Token.sol';
import './Math.sol';
import './repricers/IVolmexRepricer.sol';
import './libs/complifi/IVault.sol';
import './interfaces/IVolmexProtocol.sol';

/**
 * @title Volmex Pool Contract
 * @author volmex.finance [security@volmexlabs.com]
 */
contract Pool is OwnableUpgradeable, PausableUpgradeable, Bronze, Token, Math, TokenMetadataGenerator {
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
        requireLock();
        _mutex = true;
        _;
        _mutex = false;
    }

    /**
     * @notice Used to prevent multiple call to view methods
     */
    modifier _viewlock_() {
        requireLock();
        _;
    }

    /**
     * @notice Used to check the pool is finalised
     */
    modifier onlyFinalized() {
        require(_finalized, 'NOT_FINALIZED');
        _;
    }

    /**
     * @notice Used to check the protocol is not settled
     */
    modifier onlyNotSettled() {
        require(!protocol.isSettled(), 'PROTOCOL_SETTLED');
        _;
    }

    /**
     * @notice Internal method for re-entry check
     */
    function requireLock() internal view {
        require(!_mutex, 'REENTRY');
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
     * @param _controller Address of the pool contract controller
     * @param _volatilityIndex Index of the volatility price in oracle
     * @param _protocolInterfaceId Bytes4 hash of the protocol's interface
     */
    function initialize(
        IVolmexRepricer _repricer,
        IVolmexProtocol _protocol,
        address _controller,
        uint256 _volatilityIndex,
        bytes4 _protocolInterfaceId
    ) external initializer {
        repricer = _repricer;

        ERC165CheckerUpgradeable.supportsInterface(address(_protocol), _protocolInterfaceId);
        require(AddressUpgradeable.isContract(address(_protocol)), 'NOT_CONTRACT');
        protocol = _protocol;

        require(_controller != address(0), 'NOT_CONTROLLER');
        controller = _controller;

        __Ownable_init();
        __Pausable_init_unchained();

        upperBoundary = protocol.volatilityCapRatio() * BONE;

        volatilityIndex = _volatilityIndex;

        denomination = protocol.volatilityCapRatio();

        setName(makeTokenName(protocol.volatilityToken().name(), protocol.collateral().name()));
        setSymbol(makeTokenSymbol(protocol.volatilityToken().symbol(), protocol.collateral().symbol()));
    }

    /**
     * @notice Used to puase the contract
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
    ) external _logs_ _lock_ onlyNotSettled {
        require(!_finalized, 'IS_FINALIZED');
        require(msg.sender == controller, 'NOT_CONTROLLER');

        baseFee = _baseFee;
        maxFee = _maxFee;
        feeAmpPrimary = _feeAmpPrimary;
        feeAmpComplement = _feeAmpComplement;

        emit LOG_SET_FEE_PARAMS(_baseFee, _maxFee, _feeAmpPrimary, _feeAmpComplement);
    }

    /**
     * @notice Used to finalise the pool with the required attributes and operations
     *
     * @dev Checks, pool is finalised, caller is controller, supplied token balance
     * should be equal
     * @dev Binds the token, and its leverage and balance
     * @dev Calculates the iniyial pool supply, mints and transfer to the controller
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
    ) external _logs_ _lock_ onlyNotSettled {
        require(!_finalized, 'IS_FINALIZED');
        require(msg.sender == controller, 'NOT_CONTROLLER');

        require(_primaryBalance == _complementBalance, 'NOT_SYMMETRIC');

        require(baseFee > 0, 'NOT_SET_FEE_PARAMS');

        pMin = _pMin;
        qMin = _qMin;
        exposureLimitPrimary = _exposureLimitPrimary;
        exposureLimitComplement = _exposureLimitComplement;

        _finalized = true;

        bind(0, address(protocol.volatilityToken()), _primaryBalance, _primaryLeverage);
        bind(
            1,
            address(protocol.inverseVolatilityToken()),
            _complementBalance,
            _complementLeverage
        );

        uint256 initPoolSupply = getDerivativeDenomination() * _primaryBalance;

        uint256 collateralDecimals = uint256(
            protocol.collateral().decimals()
        );
        if (collateralDecimals >= 0 && collateralDecimals < 18) {
            initPoolSupply = initPoolSupply * (10**(18 - collateralDecimals));
        }

        _mintPoolShare(initPoolSupply);
        _pushPoolShare(msg.sender, initPoolSupply);
    }

    /**
     * @notice Used to bind the token, and its leverage and balance
     *
     * @dev This method will transfer the provided assets balance to pool from controller
     */
    function bind(
        uint256 index,
        address token,
        uint256 balance,
        uint256 leverage
    ) internal {
        require(balance >= qMin, 'MIN_BALANCE');
        require(leverage > 0, 'ZERO_LEVERAGE');

        _records[token] = Record({ leverage: leverage, balance: balance });

        _tokens[index] = token;

        _pullUnderlying(token, msg.sender, balance);
    }

    /**
     * @notice Used to add liquidity to the pool
     *
     * @dev The token amount in of the pool will be calculated and pulled from LP
     *
     * @param poolAmountOut Amount of pool token mint and transfer to LP
     * @param maxAmountsIn Max amount of pool assets an LP can supply
     */
    function joinPool(uint256 poolAmountOut, uint256[2] calldata maxAmountsIn)
        external
        _logs_
        _lock_
        onlyFinalized
    {
        uint256 poolTotal = totalSupply();
        uint256 ratio = div(poolAmountOut, poolTotal);
        require(ratio != 0, 'MATH_APPROX');

        for (uint256 i = 0; i < BOUND_TOKENS; i++) {
            address token = _tokens[i];
            uint256 bal = _records[token].balance;
            // This can't be tested, as the div method will fail, due to zero supply of lp token
            // The supply of lp token is greater than zero, means token reserve is greater than zero
            // Also, in the case of swap, there's some amount of tokens available pool more than qMin
            require(bal > 0, 'NO_BALANCE');
            uint256 tokenAmountIn = mul(ratio, bal);
            require(tokenAmountIn <= maxAmountsIn[i], 'LIMIT_IN');
            _records[token].balance = add(_records[token].balance, tokenAmountIn);
            emit LOG_JOIN(msg.sender, token, tokenAmountIn);
            _pullUnderlying(token, msg.sender, tokenAmountIn);
        }

        _mintPoolShare(poolAmountOut);
        _pushPoolShare(msg.sender, poolAmountOut);
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
    function exitPool(uint256 poolAmountIn, uint256[2] calldata minAmountsOut)
        external
        _logs_
        _lock_
        onlyFinalized
    {
        uint256 poolTotal = totalSupply();
        uint256 ratio = div(poolAmountIn, poolTotal);
        require(ratio != 0, 'MATH_APPROX');

        _pullPoolShare(msg.sender, poolAmountIn);
        _burnPoolShare(poolAmountIn);

        for (uint256 i = 0; i < BOUND_TOKENS; i++) {
            address token = _tokens[i];
            uint256 bal = _records[token].balance;
            require(bal > 0, 'NO_BALANCE');
            uint256 tokenAmountOut = mul(ratio, bal);
            require(tokenAmountOut >= minAmountsOut[i], 'LIMIT_OUT');
            _records[token].balance = sub(_records[token].balance, tokenAmountOut);
            emit LOG_EXIT(msg.sender, token, tokenAmountOut);
            _pushUnderlying(token, msg.sender, tokenAmountOut);
        }
    }

    /**
     * @notice Used to swap the pool asset
     *
     * @dev Checks the token address, should be different
     * @dev token amoint in should be greater than qMin
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
        uint256 minAmountOut
    )
        external
        _logs_
        _lock_
        whenNotPaused
        onlyFinalized
        onlyNotSettled
        returns (uint256 tokenAmountOut, uint256 spotPriceAfter)
    {
        require(tokenIn != tokenOut, 'SAME_TOKEN');
        require(tokenAmountIn >= qMin, 'MIN_TOKEN_IN');

        reprice();

        Record memory inRecord = _records[tokenIn];
        Record memory outRecord = _records[tokenOut];

        require(
            tokenAmountIn <=
                mul(min(getLeveragedBalance(inRecord), inRecord.balance), MAX_IN_RATIO),
            'MAX_IN_RATIO'
        );

        tokenAmountOut = calcOutGivenIn(
            getLeveragedBalance(inRecord),
            getLeveragedBalance(outRecord),
            tokenAmountIn,
            0
        );

        (uint256 fee,) = calcFee(
            inRecord,
            tokenAmountIn,
            outRecord,
            tokenAmountOut,
            _getPrimaryDerivativeAddress() == tokenIn ? feeAmpPrimary : feeAmpComplement
        );

        uint256 spotPriceBefore =
            calcSpotPrice(
                getLeveragedBalance(inRecord),
                getLeveragedBalance(outRecord),
                0
            );

        tokenAmountOut = calcOutGivenIn(
            getLeveragedBalance(inRecord),
            getLeveragedBalance(outRecord),
            tokenAmountIn,
            fee
        );
        require(tokenAmountOut >= minAmountOut, 'LIMIT_OUT');

        spotPriceAfter = performSwap(
            tokenIn,
            tokenAmountIn,
            tokenOut,
            tokenAmountOut,
            spotPriceBefore,
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
    function reprice() internal virtual {
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

    function performSwap(
        address tokenIn,
        uint256 tokenAmountIn,
        address tokenOut,
        uint256 tokenAmountOut,
        uint256 spotPriceBefore,
        uint256 fee
    ) internal returns (uint256 spotPriceAfter) {
        Record storage inRecord = _records[tokenIn];
        Record storage outRecord = _records[tokenOut];

        // TODO: Need to understand this and it's sub/used method
        requireBoundaryConditions(
            inRecord,
            tokenAmountIn,
            outRecord,
            tokenAmountOut,
            _getPrimaryDerivativeAddress() == tokenIn
                ? exposureLimitPrimary
                : exposureLimitComplement
        );

        updateLeverages(inRecord, tokenAmountIn, outRecord, tokenAmountOut);

        inRecord.balance = add(inRecord.balance, tokenAmountIn);
        outRecord.balance = sub(outRecord.balance, tokenAmountOut);

        spotPriceAfter = calcSpotPrice(
            getLeveragedBalance(inRecord),
            getLeveragedBalance(outRecord),
            0
        );

        // spotPriceAfter will remain larger, becasue after swap, the out token
        // balance will decrease. equation -> leverageBalance(inToken) / leverageBalance(outToken)
        require(spotPriceAfter >= spotPriceBefore, 'MATH_APPROX');
        // spotPriceBefore will remain smaller, because tokenAmountOut will be smaller than tokenAmountIn
        // because of the fee and oracle price.
        require(spotPriceBefore <= div(tokenAmountIn, tokenAmountOut), 'MATH_APPROX_OTHER');

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

        _pullUnderlying(tokenIn, msg.sender, tokenAmountIn);
        _pushUnderlying(tokenOut, msg.sender, tokenAmountOut);
    }

//    // Method temporary is not available for external usage.
//    function swapExactAmountOut(
//        address tokenIn,
//        uint256 maxAmountIn,
//        address tokenOut,
//        uint256 tokenAmountOut
//    )
//        private
//        _logs_
//        _lock_
//        whenNotPaused
//        onlyFinalized
//        onlyLiveDerivative
//        returns (uint256 tokenAmountIn, uint256 spotPriceAfter)
//    {
//        require(tokenIn != tokenOut, 'SAME_TOKEN');
//        require(tokenAmountOut >= qMin, 'MIN_TOKEN_OUT');
//
//        reprice();
//
//        Record memory inRecord = _records[tokenIn];
//        Record memory outRecord = _records[tokenOut];
//
//        require(
//            tokenAmountOut <=
//                mul(min(getLeveragedBalance(outRecord), outRecord.balance), MAX_OUT_RATIO),
//            'MAX_OUT_RATIO'
//        );
//
//        tokenAmountIn = calcInGivenOut(
//            getLeveragedBalance(inRecord),
//            getLeveragedBalance(outRecord),
//            tokenAmountOut,
//            0
//        );
//
//        uint256 fee;
//        int256 expStart;
//        (fee, expStart) = calcFee(
//            inRecord,
//            tokenAmountIn,
//            outRecord,
//            tokenAmountOut,
//            _getPrimaryDerivativeAddress() == tokenIn ? feeAmpPrimary : feeAmpComplement
//        );
//
//        uint256 spotPriceBefore =
//            calcSpotPrice(
//                getLeveragedBalance(inRecord),
//                getLeveragedBalance(outRecord),
//                0
//            );
//
//        tokenAmountIn = calcInGivenOut(
//            getLeveragedBalance(inRecord),
//            getLeveragedBalance(outRecord),
//            tokenAmountOut,
//            fee
//        );
//
//        require(tokenAmountIn <= maxAmountIn, 'LIMIT_IN');
//
//        spotPriceAfter = performSwap(
//            tokenIn,
//            tokenAmountIn,
//            tokenOut,
//            tokenAmountOut,
//            spotPriceBefore,
//            fee
//        );
//    }

    function getLeveragedBalance(Record memory r) internal pure returns (uint256) {
        return mul(r.balance, r.leverage);
    }

    function requireBoundaryConditions(
        Record storage inToken,
        uint256 tokenAmountIn,
        Record storage outToken,
        uint256 tokenAmountOut,
        uint256 exposureLimit
    ) internal view {
        require(sub(getLeveragedBalance(outToken), tokenAmountOut) > qMin, 'BOUNDARY_LEVERAGED');
        require(sub(outToken.balance, tokenAmountOut) > qMin, 'BOUNDARY_NON_LEVERAGED');

        uint256 lowerBound = div(pMin, sub(upperBoundary, pMin));
        uint256 upperBound = div(sub(upperBoundary, pMin), pMin);
        uint256 value = div(
            add(getLeveragedBalance(inToken), tokenAmountIn),
            sub(getLeveragedBalance(outToken), tokenAmountOut)
        );

        require(lowerBound < value, 'BOUNDARY_LOWER');
        require(value < upperBound, 'BOUNDARY_UPPER');

        (uint256 numerator, bool sign) = subSign(
            add(add(inToken.balance, tokenAmountIn), tokenAmountOut),
            outToken.balance
        );

        if (!sign) {
            uint256 denominator = sub(
                add(add(inToken.balance, tokenAmountIn), outToken.balance),
                tokenAmountOut
            );

            require(div(numerator, denominator) < exposureLimit, 'BOUNDARY_EXPOSURE');
        }
    }

    function updateLeverages(
        Record memory inToken,
        uint256 tokenAmountIn,
        Record memory outToken,
        uint256 tokenAmountOut
    ) internal pure {
        outToken.leverage = div(
            sub(getLeveragedBalance(outToken), tokenAmountOut),
            sub(outToken.balance, tokenAmountOut)
        );
        require(outToken.leverage > 0, 'ZERO_OUT_LEVERAGE');

        inToken.leverage = div(
            add(getLeveragedBalance(inToken), tokenAmountIn),
            add(inToken.balance, tokenAmountIn)
        );
        require(inToken.leverage > 0, 'ZERO_IN_LEVERAGE');
    }

    function getDerivativeDenomination() internal view returns (uint256) {
        // TODO: As per the inspection denomination equals 2,
        // the amount of collateral used to mint both derivatives.
        // denomination =
        //     derivativeVault
        //         .derivativeSpecification()
        //         .primaryNominalValue() +
        //     derivativeVault
        //         .derivativeSpecification()
        //         .complementNominalValue();

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
        EIP20NonStandardInterface(erc20).transferFrom(from, address(this), amount);

        bool success;
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
        require(success, 'TOKEN_TRANSFER_IN_FAILED');

        // Calculate the amount that was *actually* transferred
        uint256 balanceAfter = IERC20(erc20).balanceOf(address(this));
        require(balanceAfter >= balanceBefore, 'TOKEN_TRANSFER_IN_OVERFLOW');
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
        require(success, 'TOKEN_TRANSFER_OUT_FAILED');
    }

    function setMin(uint256 _qMin) external {
        qMin = _qMin;
    }

    function spow3(int256 _value) internal pure returns (int256) {
        return (((_value * _value) / iBONE) * _value) / iBONE;
    }

    function calcExpEndFee(
        int256[3] memory _inRecord,
        int256[3] memory _outRecord,
        int256 _baseFee,
        int256 _feeAmp,
        int256 _expEnd
    ) internal pure returns (int256) {
        int256 inBalanceLeveraged = getLeveragedBalanceOfFee(_inRecord[0], _inRecord[1]);
        int256 tokenAmountIn1 =
            inBalanceLeveraged * (_outRecord[0] - _inRecord[0]) /
                (inBalanceLeveraged + getLeveragedBalanceOfFee(_outRecord[0], _outRecord[1]));

        int256 inBalanceLeveragedChanged = inBalanceLeveraged + _inRecord[2] * iBONE;
        int256 tokenAmountIn2 =
            inBalanceLeveragedChanged * (_inRecord[0] - _outRecord[0] + _inRecord[2] + _outRecord[2]) /
            (inBalanceLeveragedChanged + getLeveragedBalanceOfFee(_outRecord[0], _outRecord[1]) - _outRecord[2] * iBONE);

        return (tokenAmountIn1 * _baseFee + tokenAmountIn2 * (_baseFee + _feeAmp * (_expEnd * _expEnd / iBONE) / 3)) /
            (tokenAmountIn1 + tokenAmountIn2);
    }

    function getLeveragedBalanceOfFee(int256 _balance, int256 _leverage)
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

        int256 _expEnd =
            ((_inRecord[0] - _outRecord[0] + _inRecord[2] + _outRecord[2]) * iBONE) /
                (_inRecord[0] + _outRecord[0] + _inRecord[2] - _outRecord[2]);

        if (expStart >= 0) {
            fee =
                _baseFee +
                (((_feeAmp) * (spow3(_expEnd) - spow3(expStart))) * iBONE) /
                (3 * (_expEnd - expStart));
        } else if (_expEnd <= 0) {
            fee = _baseFee;
        } else {
            fee = calcExpEndFee(_inRecord, _outRecord, _baseFee, _feeAmp, _expEnd);
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
    ) internal returns (uint256 fee, int256 expStart) {
        int256 ifee;
        (ifee, expStart) = calc(
            [int256(inRecord.balance), int256(inRecord.leverage), int256(tokenAmountIn)],
            [int256(outRecord.balance), int256(outRecord.leverage), int256(tokenAmountOut)],
            int256(baseFee),
            int256(feeAmp),
            int256(maxFee)
        );
        require(ifee > 0, 'BAD_FEE');
        fee = uint256(ifee);
    }

    function calcExpStart(int256 _inBalance, int256 _outBalance) internal pure returns (int256) {
        return ((_inBalance - _outBalance) * iBONE) / (_inBalance + _outBalance);
    }
}

// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.7.6;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "./libs/complifi/tokens/IERC20Metadata.sol";
import "./libs/complifi/tokens/EIP20NonStandardInterface.sol";
import "./libs/complifi/tokens/TokenMetadataGenerator.sol";

import "./Token.sol";
import "./Math.sol";
import "./repricers/IVolmexRepricer.sol";
import "./IDynamicFee.sol";
import "./libs/complifi/IVault.sol";
import "./interfaces/IVolmexProtocol.sol";

contract Pool is
    Ownable,
    Pausable,
    Bronze,
    Token,
    Math,
    TokenMetadataGenerator
{
    struct Record {
        uint256 leverage;
        uint256 balance;
    }

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

    event LOG_JOIN(
        address indexed caller,
        address indexed tokenIn,
        uint256 tokenAmountIn
    );

    event LOG_EXIT(
        address indexed caller,
        address indexed tokenOut,
        uint256 tokenAmountOut
    );

    event LOG_REPRICE(
        uint256 repricingBlock,
        uint256 balancePrimary,
        uint256 balanceComplement,
        uint256 leveragePrimary,
        uint256 leverageComplement,
        uint256 newLeveragePrimary,
        uint256 newLeverageComplement,
        int256 estPricePrimary,
        int256 estPriceComplement,
        int256 liveUnderlingValue
    );

    event LOG_SET_FEE_PARAMS(
        uint256 baseFee,
        uint256 maxFee,
        uint256 feeAmpPrimary,
        uint256 feeAmpComplement
    );

    event LOG_CALL(
        bytes4 indexed sig,
        address indexed caller,
        bytes data
    ) anonymous;

    modifier _logs_() {
        emit LOG_CALL(msg.sig, msg.sender, msg.data);
        _;
    }

    modifier _lock_() {
        requireLock();
        _mutex = true;
        _;
        _mutex = false;
    }

    modifier _viewlock_() {
        requireLock();
        _;
    }

    modifier onlyFinalized() {
        require(_finalized, "NOT_FINALIZED");
        _;
    }

    modifier onlyNotSettled() {
        require(!protocol.isSettled(), "PROTOCOL_SETTLED");
        _;
    }

    function requireLock() internal view {
        require(!_mutex, "REENTRY");
    }

    bool private _mutex;

    address private controller; // has CONTROL role

    // `finalize` sets `PUBLIC can SWAP`, `PUBLIC can JOIN`
    bool private _finalized;

    uint256 public constant BOUND_TOKENS = 2;
    address[BOUND_TOKENS] private _tokens;
    mapping(address => Record) internal _records;

    uint256 public repricingBlock;
    uint256 public upperBoundary;

    uint256 public baseFee;
    uint256 public feeAmpPrimary;
    uint256 public feeAmpComplement;
    uint256 public maxFee;

    uint256 public pMin;
    uint256 public qMin;
    uint256 public exposureLimitPrimary;
    uint256 public exposureLimitComplement;
    uint256 public repricerParam1;
    uint256 public repricerParam2;

    IVault public derivativeVault;
    IDynamicFee public dynamicFee;
    IVolmexRepricer public repricer;
    IVolmexProtocol public protocol;

    uint256 public spotPrice;
    string private volatilitySymbol;

    constructor(
        IVault _derivativeVault,
        IDynamicFee _dynamicFee,
        IVolmexRepricer _repricer,
        IVolmexProtocol _protocol,
        address _controller
    ) public {
        derivativeVault = _derivativeVault;
        dynamicFee = _dynamicFee;
        repricer = _repricer;
        protocol = _protocol;

        require(_controller != address(0), "NOT_CONTROLLER");
        controller = _controller;

        string memory settlementDate = formatDate(
            derivativeVault.settleTime()
        );

        setName(
            makeTokenName(
                derivativeVault.derivativeSpecification().name(),
                settlementDate,
                " LP"
            )
        );
        setSymbol(
            makeTokenSymbol(
                derivativeVault.derivativeSpecification().symbol(),
                settlementDate,
                "-LP"
            )
        );
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function isFinalized() external view returns (bool) {
        return _finalized;
    }

    function getTokens()
        external
        view
        _viewlock_
        returns (address[BOUND_TOKENS] memory tokens)
    {
        return _tokens;
    }

    function getLeverage(address token)
        external
        view
        _viewlock_
        returns (uint256)
    {
        return _records[token].leverage;
    }

    function getBalance(address token)
        external
        view
        _viewlock_
        returns (uint256)
    {
        return _records[token].balance;
    }

    function setFeeParams(
        uint256 _baseFee,
        uint256 _maxFee,
        uint256 _feeAmpPrimary,
        uint256 _feeAmpComplement
    ) external _logs_ _lock_ onlyNotSettled {
        require(!_finalized, "IS_FINALIZED");
        require(msg.sender == controller, "NOT_CONTROLLER");

        baseFee = _baseFee;
        maxFee = _maxFee;
        feeAmpPrimary = _feeAmpPrimary;
        feeAmpComplement = _feeAmpComplement;

        emit LOG_SET_FEE_PARAMS(
            _baseFee,
            _maxFee,
            _feeAmpPrimary,
            _feeAmpComplement
        );
    }

    function finalize(
        uint256 _primaryBalance,
        uint256 _primaryLeverage,
        uint256 _complementBalance,
        uint256 _complementLeverage,
        uint256 _exposureLimitPrimary,
        uint256 _exposureLimitComplement,
        uint256 _pMin,
        uint256 _qMin,
        uint256 _repricerParam1,
        uint256 _repricerParam2,
        string calldata _volatilitySymbol
    ) external _logs_ _lock_ onlyNotSettled {
        require(!_finalized, "IS_FINALIZED");
        require(msg.sender == controller, "NOT_CONTROLLER");

        require(
            _primaryBalance == _complementBalance,
            "NOT_SYMMETRIC"
        );

        require(baseFee > 0, "NOT_SET_FEE_PARAMS");

        pMin = _pMin;
        qMin = _qMin;
        exposureLimitPrimary = _exposureLimitPrimary;
        exposureLimitComplement = _exposureLimitComplement;
        repricerParam1 = _repricerParam1;
        repricerParam2 = _repricerParam2;
        volatilitySymbol = _volatilitySymbol;

        _finalized = true;

        bind(
            0,
            address(derivativeVault.primaryToken()),
            _primaryBalance,
            _primaryLeverage
        );
        bind(
            1,
            address(derivativeVault.complementToken()),
            _complementBalance,
            _complementLeverage
        );

        uint256 initPoolSupply = getDerivativeDenomination() *
            _primaryBalance;

        uint256 collateralDecimals = uint256(
            IERC20Metadata(address(derivativeVault.collateralToken()))
                .decimals()
        );
        if (collateralDecimals >= 0 && collateralDecimals < 18) {
            initPoolSupply =
                initPoolSupply *
                (10**(18 - collateralDecimals));
        }

        _mintPoolShare(initPoolSupply);
        _pushPoolShare(msg.sender, initPoolSupply);
    }

    function bind(
        uint256 index,
        address token,
        uint256 balance,
        uint256 leverage
    ) internal {
        require(balance >= qMin, "MIN_BALANCE");
        require(leverage > 0, "ZERO_LEVERAGE");

        _records[token] = Record({
            leverage: leverage,
            balance: balance
        });

        _tokens[index] = token;

        _pullUnderlying(token, msg.sender, balance);
    }

    function joinPool(
        uint256 poolAmountOut,
        uint256[2] calldata maxAmountsIn
    ) external _logs_ _lock_ onlyFinalized {
        uint256 poolTotal = totalSupply();
        uint256 ratio = div(poolAmountOut, poolTotal);
        require(ratio != 0, "MATH_APPROX");

        for (uint256 i = 0; i < BOUND_TOKENS; i++) {
            address token = _tokens[i];
            uint256 bal = _records[token].balance;
            require(bal > 0, "NO_BALANCE");
            uint256 tokenAmountIn = mul(ratio, bal);
            require(tokenAmountIn <= maxAmountsIn[i], "LIMIT_IN");
            _records[token].balance = add(
                _records[token].balance,
                tokenAmountIn
            );
            emit LOG_JOIN(msg.sender, token, tokenAmountIn);
            _pullUnderlying(token, msg.sender, tokenAmountIn);
        }

        _mintPoolShare(poolAmountOut);
        _pushPoolShare(msg.sender, poolAmountOut);
    }

    function exitPool(
        uint256 poolAmountIn,
        uint256[2] calldata minAmountsOut
    ) external _logs_ _lock_ onlyFinalized {
        uint256 poolTotal = totalSupply();
        uint256 ratio = div(poolAmountIn, poolTotal);
        require(ratio != 0, "MATH_APPROX");

        _pullPoolShare(msg.sender, poolAmountIn);
        _burnPoolShare(poolAmountIn);

        for (uint256 i = 0; i < BOUND_TOKENS; i++) {
            address token = _tokens[i];
            uint256 bal = _records[token].balance;
            require(bal > 0, "NO_BALANCE");
            uint256 tokenAmountOut = mul(ratio, bal);
            require(tokenAmountOut >= minAmountsOut[i], "LIMIT_OUT");
            _records[token].balance = sub(
                _records[token].balance,
                tokenAmountOut
            );
            emit LOG_EXIT(msg.sender, token, tokenAmountOut);
            _pushUnderlying(token, msg.sender, tokenAmountOut);
        }
    }

    function reprice(
        uint256 balanceIn,
        uint256 balanceOut,
        uint256 tokenAmountIn
    ) internal virtual {
        if (repricingBlock == block.number) return;
        repricingBlock = block.number;

        (spotPrice) = repricer.reprice(
            balanceIn,
            balanceOut,
            tokenAmountIn,
            volatilitySymbol
        );
    }

    function calcFee(
        Record memory inRecord,
        uint256 tokenAmountIn,
        Record memory outRecord,
        uint256 tokenAmountOut,
        uint256 feeAmp
    ) internal returns (uint256 fee, int256 expStart) {
        int256 ifee;
        (ifee, expStart) = dynamicFee.calc(
            [
                int256(inRecord.balance),
                int256(inRecord.leverage),
                int256(tokenAmountIn)
            ],
            [
                int256(outRecord.balance),
                int256(outRecord.leverage),
                int256(tokenAmountOut)
            ],
            int256(baseFee),
            int256(feeAmp),
            int256(maxFee)
        );
        require(ifee > 0, "BAD_FEE");
        fee = uint256(ifee);
    }

    function calcExpStart(int256 _inBalance, int256 _outBalance)
        internal
        pure
        returns (int256)
    {
        return
            ((_inBalance - _outBalance) * iBONE) /
            (_inBalance + _outBalance);
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

        requireBoundaryConditions(
            inRecord,
            tokenAmountIn,
            outRecord,
            tokenAmountOut,
            _getPrimaryDerivativeAddress() == tokenIn
                ? exposureLimitPrimary
                : exposureLimitComplement
        );

        updateLeverages(
            inRecord,
            tokenAmountIn,
            outRecord,
            tokenAmountOut
        );

        inRecord.balance = add(inRecord.balance, tokenAmountIn);
        outRecord.balance = sub(outRecord.balance, tokenAmountOut);

        spotPriceAfter = calcSpotPrice(
            getLeveragedBalance(inRecord),
            getLeveragedBalance(outRecord),
            0
        );

        require(spotPriceAfter >= spotPriceBefore, "MATH_APPROX");
        require(
            spotPriceBefore <= div(tokenAmountIn, tokenAmountOut),
            "MATH_APPROX_OTHER"
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

        _pullUnderlying(tokenIn, msg.sender, tokenAmountIn);
        _pushUnderlying(tokenOut, msg.sender, tokenAmountOut);
    }

    function swapExactAmountIn(
        address tokenIn,
        uint256 tokenAmountIn,
        address tokenOut,
        uint256 minAmountOut
    )
        external
        whenNotPaused
        onlyFinalized
        onlyNotSettled
        returns (uint256 tokenAmountOut)
    {
        require(tokenIn != tokenOut, "SAME_TOKEN");
        require(tokenAmountIn >= qMin, "MIN_TOKEN_IN");

        Record storage inRecord = _records[tokenIn];
        Record storage outRecord = _records[tokenOut];

        reprice(inRecord.balance, outRecord.balance, tokenAmountIn);

        uint256 fee;
        (fee, ) = calcFee(
            inRecord,
            tokenAmountIn,
            outRecord,
            tokenAmountOut,
            feeAmpPrimary
        );

        tokenAmountOut = calcOutGivenIn(
            getLeveragedBalance(inRecord),
            getLeveragedBalance(outRecord),
            tokenAmountIn,
            fee
        );
        require(tokenAmountOut >= minAmountOut, "LIMIT_OUT");
        require(
            outRecord.balance >= tokenAmountOut,
            "INSUFFICIENT_BALANCE"
        );

        updateLeverages(
            inRecord,
            tokenAmountIn,
            outRecord,
            tokenAmountOut
        );

        inRecord.balance = add(inRecord.balance, tokenAmountIn);
        outRecord.balance = sub(outRecord.balance, tokenAmountOut);

        emit LOG_SWAP(
            msg.sender,
            tokenIn,
            tokenOut,
            tokenAmountIn,
            tokenAmountOut,
            baseFee,
            inRecord.balance,
            outRecord.balance,
            inRecord.leverage,
            outRecord.leverage
        );

        _pullUnderlying(tokenIn, msg.sender, tokenAmountIn);
        _pushUnderlying(tokenOut, msg.sender, tokenAmountOut);
    }

    // function swapExactAmountIn(
    //     address tokenIn,
    //     uint256 tokenAmountIn,
    //     address tokenOut,
    //     uint256 minAmountOut
    // )
    //     external
    //     _logs_
    //     _lock_
    //     whenNotPaused
    //     onlyFinalized
    //     returns (uint256 tokenAmountOut, uint256 spotPriceAfter)
    // {
    //     require(tokenIn != tokenOut, 'SAME_TOKEN');
    //     require(tokenAmountIn >= qMin, 'MIN_TOKEN_IN');

    //     reprice();

    //     Record memory inRecord = _records[tokenIn];
    //     Record memory outRecord = _records[tokenOut];

    //     require(
    //         tokenAmountIn <=
    //             mul(min(getLeveragedBalance(inRecord), inRecord.balance), MAX_IN_RATIO),
    //         'MAX_IN_RATIO'
    //     );

    //     tokenAmountOut = calcOutGivenIn(
    //         getLeveragedBalance(inRecord),
    //         getLeveragedBalance(outRecord),
    //         tokenAmountIn,
    //         0
    //     );

    //     uint256 fee;
    //     int256 expStart;
    //     (fee, expStart) = calcFee(
    //         inRecord,
    //         tokenAmountIn,
    //         outRecord,
    //         tokenAmountOut,
    //         _getPrimaryDerivativeAddress() == tokenIn ? feeAmpPrimary : feeAmpComplement
    //     );

    //     uint256 spotPriceBefore =
    //         calcSpotPrice(
    //             getLeveragedBalance(inRecord),
    //             getLeveragedBalance(outRecord),
    //             0
    //         );

    //     tokenAmountOut = calcOutGivenIn(
    //         getLeveragedBalance(inRecord),
    //         getLeveragedBalance(outRecord),
    //         tokenAmountIn,
    //         fee
    //     );
    //     require(tokenAmountOut >= minAmountOut, 'LIMIT_OUT');

    //     spotPriceAfter = performSwap(
    //         tokenIn,
    //         tokenAmountIn,
    //         tokenOut,
    //         tokenAmountOut,
    //         spotPriceBefore,
    //         fee
    //     );
    // }

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

    function getLeveragedBalance(Record memory r)
        internal
        pure
        returns (uint256)
    {
        return mul(r.balance, r.leverage);
    }

    function requireBoundaryConditions(
        Record storage inToken,
        uint256 tokenAmountIn,
        Record storage outToken,
        uint256 tokenAmountOut,
        uint256 exposureLimit
    ) internal view {
        require(
            sub(getLeveragedBalance(outToken), tokenAmountOut) > qMin,
            "BOUNDARY_LEVERAGED"
        );
        require(
            sub(outToken.balance, tokenAmountOut) > qMin,
            "BOUNDARY_NON_LEVERAGED"
        );

        uint256 lowerBound = div(pMin, sub(upperBoundary, pMin));
        uint256 upperBound = div(sub(upperBoundary, pMin), pMin);
        uint256 value = div(
            add(getLeveragedBalance(inToken), tokenAmountIn),
            sub(getLeveragedBalance(outToken), tokenAmountOut)
        );

        require(lowerBound < value, "BOUNDARY_LOWER");
        require(value < upperBound, "BOUNDARY_UPPER");

        (uint256 numerator, bool sign) = subSign(
            add(add(inToken.balance, tokenAmountIn), tokenAmountOut),
            outToken.balance
        );

        if (!sign) {
            uint256 denominator = sub(
                add(
                    add(inToken.balance, tokenAmountIn),
                    outToken.balance
                ),
                tokenAmountOut
            );

            require(
                div(numerator, denominator) < exposureLimit,
                "BOUNDARY_EXPOSURE"
            );
        }
    }

    function updateLeverages(
        Record storage inToken,
        uint256 tokenAmountIn,
        Record storage outToken,
        uint256 tokenAmountOut
    ) internal {
        outToken.leverage = div(
            sub(getLeveragedBalance(outToken), tokenAmountOut),
            sub(outToken.balance, tokenAmountOut)
        );
        require(outToken.leverage > 0, "ZERO_OUT_LEVERAGE");

        inToken.leverage = div(
            add(getLeveragedBalance(inToken), tokenAmountIn),
            add(inToken.balance, tokenAmountIn)
        );
        require(inToken.leverage > 0, "ZERO_IN_LEVERAGE");
    }

    function getDerivativeDenomination()
        internal
        view
        returns (uint256 denomination)
    {
        denomination =
            derivativeVault
                .derivativeSpecification()
                .primaryNominalValue() +
            derivativeVault
                .derivativeSpecification()
                .complementNominalValue();
    }

    function _getPrimaryDerivativeAddress()
        internal
        view
        returns (address)
    {
        return _tokens[0];
    }

    function _getComplementDerivativeAddress()
        internal
        view
        returns (address)
    {
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
        uint256 balanceBefore = IERC20(erc20).balanceOf(
            address(this)
        );
        EIP20NonStandardInterface(erc20).transferFrom(
            from,
            address(this),
            amount
        );

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
        require(success, "TOKEN_TRANSFER_IN_FAILED");

        // Calculate the amount that was *actually* transferred
        uint256 balanceAfter = IERC20(erc20).balanceOf(address(this));
        require(
            balanceAfter >= balanceBefore,
            "TOKEN_TRANSFER_IN_OVERFLOW"
        );
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
        require(success, "TOKEN_TRANSFER_OUT_FAILED");
    }
}

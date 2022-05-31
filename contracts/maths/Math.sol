// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.11;

import "abdk-libraries-solidity/ABDKMathQuad.sol";

import "./Num.sol";
import "../interfaces/IVolmexPool.sol";

contract Math is Num {
    /**********************************************************************************************
    // calcSpotPrice                                                                             //
    // sP = spotPrice                                                                            //
    // bI = tokenBalanceIn                 bI          1                                         //
    // bO = tokenBalanceOut         sP =  ----  *  ----------                                    //
    // sF = swapFee                        bO      ( 1 - sF )                                    //
    **********************************************************************************************/
    function calcSpotPrice(
        uint256 _tokenBalanceIn,
        uint256 _tokenBalanceOut,
        uint256 _swapFee
    ) public pure returns (uint256 spotPrice) {
        uint256 ratio = _div(_tokenBalanceIn, _tokenBalanceOut);
        uint256 scale = _div(BONE, BONE - _swapFee);
        spotPrice = _mul(ratio, scale);
    }

    /**********************************************************************************************
    // calcOutGivenIn                                                                            //
    // aO = tokenAmountOut                                                                       //
    // bO = tokenBalanceOut                                                                      //
    // bI = tokenBalanceIn              /      /            bI             \   \                 //
    // aI = tokenAmountIn    aO = bO * |  1 - | --------------------------  |  |                 //
    // sF = swapFee                     \      \ ( bI + ( aI * ( 1 - sF )) /   /                 //
    **********************************************************************************************/
    function _calcOutGivenIn(
        uint256 _tokenBalanceIn,
        uint256 _tokenBalanceOut,
        uint256 _tokenAmountIn,
        uint256 _swapFee
    ) internal pure returns (uint256 tokenAmountOut) {
        uint256 adjustedIn = BONE - _swapFee;
        adjustedIn = _mul(_tokenAmountIn, adjustedIn);
        uint256 y = _div(_tokenBalanceIn, _tokenBalanceIn + adjustedIn);
        uint256 bar = BONE - y;
        tokenAmountOut = _mul(_tokenBalanceOut, bar);
    }

    /**
     * @notice Used to calculate the out amount after fee deduction
     */
    function _calculateAmountOut(
        uint256 _poolAmountIn,
        uint256 _ratio,
        uint256 _tokenReserve,
        uint256 _upperBoundary,
        uint256 _adminFee
    ) internal pure returns (uint256 amountOut, uint256 feeAmount) {
        uint256 tokenAmount = _mul(_div(_poolAmountIn, _upperBoundary), BONE);
        amountOut = _mul(_ratio, _tokenReserve);
        if (amountOut > tokenAmount) {
            feeAmount = _div(_mul(tokenAmount, _adminFee), 10000);
            amountOut = amountOut - feeAmount;
        }
    }

    /**
     * @notice Used to calculate the collateral/volatility amount after interaction with VolmexProtocol
     */
    function _calculateAssetQuantity(
        uint256 _amount,
        uint256 _feePercent,
        bool _isVolatilityRequired,
        uint256 _volatilityCapRatio,
        uint256 _precisionRatio
    ) internal pure returns (uint256 amount, uint256 protocolFee) {
        uint256 effectiveAmount = _isVolatilityRequired ? _amount : _amount / _precisionRatio;

        protocolFee = ((effectiveAmount * _feePercent) / 10000);
        effectiveAmount = effectiveAmount - protocolFee;

        amount = _isVolatilityRequired
            ? (effectiveAmount / _volatilityCapRatio) * _precisionRatio
            : effectiveAmount;
    }

    /**
     * @notice Used to calculate the amountIn and amountOut, provided max amount
     */
    function _getSwappedAssetAmount(
        address _tokenIn,
        uint256 _maxAmountIn,
        IVolmexPool _pool,
        bool _isInverse
    )
        internal
        view
        returns (
            uint256 swapAmount,
            uint256 amountOut,
            uint256 fee
        )
    {
        uint256 leverageBalance = _mul(
            _pool.getLeverage(_pool.tokens(0)),
            _pool.getBalance(_pool.tokens(0))
        );
        uint256 iLeverageBalance = _mul(
            _pool.getLeverage(_pool.tokens(1)),
            _pool.getBalance(_pool.tokens(1))
        );

        swapAmount = _volatililtyAmountToSwap(
            _maxAmountIn,
            _isInverse ? iLeverageBalance : leverageBalance,
            _isInverse ? leverageBalance : iLeverageBalance,
            0
        );
        (amountOut, fee) = _pool.getTokenAmountOut(_tokenIn, swapAmount);
        swapAmount = _volatililtyAmountToSwap(
            _maxAmountIn,
            _isInverse ? iLeverageBalance : leverageBalance,
            _isInverse ? leverageBalance : iLeverageBalance,
            fee
        );
        (amountOut, fee) = _pool.getTokenAmountOut(_tokenIn, swapAmount);
    }

    /**
     * Reference: https://excalidraw.com/#json=Rg2qV51HsIX2OoRZVQ-FK,9Y3xGthsEf1sXnB_H4V7Zw
     */
    function _volatililtyAmountToSwap(
        uint256 _maxAmount,
        uint256 _leverageBalanceOfIn,
        uint256 _leverageBalanceOfOut,
        uint256 _fee
    ) private pure returns (uint256 swapAmount) {
        uint256 R = BONE - _fee;
        uint256 B = ((_leverageBalanceOfIn * BONE) +
            (_leverageBalanceOfOut * R) -
            (_maxAmount * R)) / 10**6;

        uint256 numerator = ABDKMathQuad.toUInt(
            ABDKMathQuad.sqrt(
                ABDKMathQuad.fromUInt(
                    (B * B) + (4 * R * _leverageBalanceOfIn * _maxAmount) * (10**6)
                )
            )
        ) - B;

        swapAmount = numerator / ((2 * R) / 10**6);
    }
}

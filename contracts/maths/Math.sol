// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.11;

import "./Num.sol";

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
}

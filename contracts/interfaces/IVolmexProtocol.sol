// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.11;

import "./IERC20Modified.sol";

interface IVolmexProtocol {
    //getter methods
    function minimumCollateralQty() external view returns (uint256);
    function active() external view returns (bool);
    function isSettled() external view returns (bool);
    function volatilityToken() external view returns (IERC20Modified);
    function inverseVolatilityToken() external view returns (IERC20Modified);
    function collateral() external view returns (IERC20Modified);
    function issuanceFees() external view returns (uint256);
    function redeemFees() external view returns (uint256);
    function accumulatedFees() external view returns (uint256);
    function volatilityCapRatio() external view returns (uint256);
    function settlementPrice() external view returns (uint256);
    function precisionRatio() external view returns (uint256);

    //setter methods
    function toggleActive() external;
    function updateMinimumCollQty(uint256 _newMinimumCollQty) external;
    function updatePositionToken(address _positionToken, bool _isVolatilityIndex) external;
    function collateralize(uint256 _collateralQty) external returns (uint256, uint256);
    function redeem(uint256 _positionTokenQty) external returns (uint256, uint256);
    function redeemSettled(
        uint256 _volatilityIndexTokenQty,
        uint256 _inverseVolatilityIndexTokenQty
    ) external returns (uint256, uint256);
    function settle(uint256 _settlementPrice) external;
    function recoverTokens(
        address _token,
        address _toWhom,
        uint256 _howMuch
    ) external;
    function updateFees(uint256 _issuanceFees, uint256 _redeemFees) external;
    function claimAccumulatedFees() external;
    function togglePause(bool _isPause) external;
}

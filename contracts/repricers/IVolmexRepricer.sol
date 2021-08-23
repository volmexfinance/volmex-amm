// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.7.6;

interface IVolmexRepricer {
    function leverageCoefficient() external view returns (uint256);

    function reprice(
        uint256 _collateralReserve,
        uint256 _volatilityReserve,
        uint256 _tradeAmount,
        string calldata _volatilitySymbol
    )
        external
        returns (
            uint256 spotPrice,
            uint256 averagePrice,
            uint256 volatilityPrice
        );
}

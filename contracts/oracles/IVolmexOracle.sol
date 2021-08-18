// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.7.6;

interface IVolmexOracle {
    function volatilityTokenPrice(string calldata volatilitySymbol) external view returns (uint256);

    function updateVolatilityTokenPrice(
        string calldata _volatilityTokenSymbol,
        uint256 _volatilityTokenPrice
    ) external;
}

// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.10

interface IVolmexOracle {
    function volatilityTokenPriceByIndex(uint256 _volatilityIndex)
        external
        view
        returns (uint256);

    function updateVolatilityTokenPrice(
        string calldata _volatilityTokenSymbol,
        uint256 _volatilityTokenPrice
    ) external;
}

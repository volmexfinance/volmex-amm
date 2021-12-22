// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.11;

interface IVolmexOracle {

    function getVolatilityTokenPriceByIndex(uint256 _index) external view returns (uint256, uint256);

    function updateVolatilityTokenPrice(
        string calldata _volatilityTokenSymbol,
        uint256 _volatilityTokenPrice
    ) external;

}

// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.7.6;

interface IVolmexOracle {
    function volatilityTokenPriceBySymbol(string calldata volatilitySymbol)
        external
        view
        returns (uint256);

    function volatilityTokenPriceByIndex(uint256 _volatilityIndex) external view returns (uint256);

    function indexCount() external returns (uint256);

    function updateVolatilityTokenPrice(
        string calldata _volatilityTokenSymbol,
        uint256 _volatilityTokenPrice
    ) external;
}

// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.11;

interface IVolmexOracle {
    function getVolatilityTokenPriceByIndex(uint256 _index)
        external
        view
        returns (uint256, uint256);

    function updateVolatilityTokenPrice(
        uint256 _volatilityIndex,
        uint256 _volatilityTokenPrice,
        uint256 _index,
        bytes32 _proofHash
    ) external;

    function updateVolatilityCapRatio(uint256 _index, uint256 _volatilityCapRatio) external;

    function addVolatilityTokenPrice(
        uint256 _volatilityTokenPrice,
        uint256 _index,
        string calldata _volatilityTokenSymbol,
        bytes32 _proofHash
    ) external;
}

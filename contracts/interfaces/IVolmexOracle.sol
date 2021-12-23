// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.11;

interface IVolmexOracle {

    function protocol() external view returns (address);

    function getVolatilityTokenPriceByIndex(uint256 _index)
        external
        view
        returns (uint256, uint256);

    function getVolatilityPriceBySymbol(string calldata _volatilityTokenSymbol)
        external
        view
        returns (uint256 volatilityTokenPrice, uint256 iVolatilityTokenPrice);

    function updateBatchVolatilityTokenPrices(
        uint256[] memory _volatilityIndexes,
        uint256[] memory _volatilityTokenPrices,
        uint256[] memory _indexes,
        bytes32[] memory _proofHashes
    ) external;

    function updateProtocol(address _protocol) external;

    function addVolatilityIndex(
        uint256 _volatilityTokenPrice,
        uint256 _volatilityCapRatio,
        string calldata _volatilityTokenSymbol,
        bytes32 _proofHash
    ) external;
}

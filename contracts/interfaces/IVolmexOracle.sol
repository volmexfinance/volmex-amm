// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.11;

import '@openzeppelin/contracts-upgradeable/utils/introspection/IERC165Upgradeable.sol';
import './IVolmexProtocol.sol';

interface IVolmexOracle is IERC165Upgradeable {
    function getVolatilityTokenPriceByIndex(uint256 _index)
        external
        view
        returns (uint256, uint256);

    function getVolatilityPriceBySymbol(string calldata _volatilityTokenSymbol)
        external
        view
        returns (uint256 volatilityTokenPrice, uint256 iVolatilityTokenPrice);

    function updateBatchVolatilityTokenPrice(
        uint256[] memory _volatilityIndexes,
        uint256[] memory _volatilityTokenPrices,
        bytes32[] memory _proofHashes
    ) external;

    function addVolatilityIndex(
        uint256 _volatilityTokenPrice,
        IVolmexProtocol _protocol,
        string calldata _volatilityTokenSymbol,
        bytes32 _proofHash
    ) external;

    function updateIndexBySymbol(string calldata _tokenSymbol, uint256 _index) external;

    function volatilityCapRatioByIndex(uint256 _index) external view returns (uint256);

    function volatilityTokenPriceProofHash(uint256 _index) external view returns (bytes32);

    function volatilityIndexBySymbol(string calldata _tokenSymbol) external view returns (uint256);

    function indexCount() external view returns (uint256);
}

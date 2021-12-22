// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.10;

import '@openzeppelin/contracts-upgradeable/utils/introspection/IERC165Upgradeable.sol';

interface IVolmexRepricer is IERC165Upgradeable {
    function protocolVolatilityCapRatio() external view returns (uint256);

    function reprice(uint256 _volatilityIndex)
        external
        view
        returns (
            uint256 estPrimaryPrice,
            uint256 estComplementPrice,
            uint256 estPrice
        );

    function sqrtWrapped(int256 value) external pure returns (int256);
}

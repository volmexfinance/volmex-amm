// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.11;

import '@openzeppelin/contracts-upgradeable/utils/introspection/IERC165Upgradeable.sol';
import './IVolmexOracle.sol';

interface IVolmexRepricer is IERC165Upgradeable {

    function reprice(uint256 _volatilityIndex)
        external
        view
        returns (
            uint256 estPrimaryPrice,
            uint256 estComplementPrice,
            uint256 estPrice
        );

    function oracle() external view returns (IVolmexOracle);

    function sqrtWrapped(int256 value) external pure returns (int256);
}

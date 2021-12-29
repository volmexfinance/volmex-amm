// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.11;

import '@openzeppelin/contracts-upgradeable/utils/introspection/IERC165Upgradeable.sol';

import './IERC20Modified.sol';

interface IVolmexController is IERC165Upgradeable {
    function transferAssetToPool(
        IERC20Modified _token,
        address _account,
        uint256 _amount
    ) external;
}
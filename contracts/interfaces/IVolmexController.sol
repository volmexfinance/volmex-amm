// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.7.6;

import './IERC20Modified.sol';

interface IVolmexController {
    function transferAssetToPool(
        IERC20Modified _token,
        address _account,
        address _pool,
        uint256 _amount
    ) external;
}
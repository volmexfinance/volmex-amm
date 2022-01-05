// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.11;

import './IERC20Modified.sol';
import './IVolmexPool.sol';

interface IFlashLoanReceiver {
    function POOL() external returns (IVolmexPool);

    function executeOperation(
        address assetToken,
        uint256 amounts,
        uint256 premiums,
        bytes calldata params
    ) external returns (bool);
}

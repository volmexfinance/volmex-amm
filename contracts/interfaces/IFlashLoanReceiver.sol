// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.7.6;

import './IERC20Modified.sol';
import './IPool.sol';

interface IFlashLoanReceiver {
    function POOL() external returns (IPool);

    function executeOperation(
        address assetToken,
        uint256 amounts,
        uint256 premiums,
        address initiator,
        bytes calldata params
    ) external returns (bool);
}

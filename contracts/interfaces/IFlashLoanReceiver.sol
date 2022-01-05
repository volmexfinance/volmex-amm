// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.11;

import './IVolmexPool.sol';

interface IFlashLoanReceiver {
    function executeOperation(
        address assetToken,
        uint256 amounts,
        uint256 premiums,
        bytes calldata params
    ) external returns (bool);
}

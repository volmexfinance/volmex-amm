// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.10

import './IERC20Modified.sol';
import './IVolmexAMM.sol';

interface IFlashLoanReceiver {
    function POOL() external returns (IVolmexAMM);

    function executeOperation(
        address assetToken,
        uint256 amounts,
        uint256 premiums,
        address initiator,
        bytes calldata params
    ) external returns (bool);
}

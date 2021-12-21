// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.10;

import '../interfaces/IFlashLoanReceiver.sol';
import '../maths/Num.sol';

contract FlashLoanExample is Num {
    /**
        This function is called after your contract has received the flash loaned amount
     */
    function executeOperation(
        address asset,
        uint256 amount,
        uint256 premium,
        address initiator,
        bytes calldata params
    ) external returns (bool) {
        //
        // This contract now has the funds requested.
        // Your logic goes here.
        //

        // At the end of your logic above, this contract owes
        // the flashloaned amounts + premiums.
        // Therefore ensure your contract has enough to repay
        // these amounts.

        // Approve the VolmexPool contract allowance to *pull* the owed amount
        uint256 amountOwing = amount + premium;
        IERC20Modified(asset).approve(address(IFlashLoanReceiver(initiator).POOL()), amountOwing);

        return true;
    }
}

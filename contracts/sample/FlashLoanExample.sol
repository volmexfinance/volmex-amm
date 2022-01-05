// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.11;

import '../interfaces/IFlashLoanReceiver.sol';
import '../maths/Num.sol';
import '../interfaces/IVolmexPool.sol';

contract FlashLoanExample is Num {
    address public pool;

    constructor(address _pool) {
        pool = _pool;
    }
    /**
        This function is called after your contract has received the flash loaned amount
     */
    function executeOperation(
        address asset,
        uint256 amount,
        uint256 premium,
        bytes memory _params
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
        IERC20Modified(asset).approve(pool, amountOwing);

        return true;
    }

    function flashLoan(address _assetToken) external {
        bytes memory data = "0x10";
        uint256 amount = 10 ether;

        IVolmexPool(pool).flashLoan(address(this), _assetToken, amount, data);
    }
}

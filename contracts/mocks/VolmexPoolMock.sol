// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.11;

import '../VolmexPool.sol';

/**
 * @title Volmex Pool Mock Contract
 * @author volmex.finance [security@volmexlabs.com]
 */
contract VolmexPoolMock is VolmexPool {
    function setControllerWithoutCheck(address _controller) external onlyOwner {
        controller = IVolmexController(_controller);

        emit ControllerSet(address(controller));
    }

    function _pullUnderlying(
        address _erc20,
        address _from,
        uint256 _amount
    ) internal override returns (uint256) {
        uint256 balanceBefore = IERC20(_erc20).balanceOf(address(this));

        address(controller) == owner()
            ? IEIP20NonStandard(_erc20).transferFrom(_from, address(this), _amount)
            : controller.transferAssetToPool(IERC20Modified(_erc20), _from, _amount);

        bool success;
        //solium-disable-next-line security/no-inline-assembly
        assembly {
            switch returndatasize()
            case 0 {
                // This is a non-standard ERC-20
                success := not(0) // set success to true
            }
            case 32 {
                // This is a compliant ERC-20
                returndatacopy(0, 0, 32)
                success := mload(0) // Set `success = returndata` of external call
            }
            default {
                // This is an excessively non-compliant ERC-20, revert.
                revert(0, 0)
            }
        }
        require(success, 'VolmexPool: Token transfer failed');

        // Calculate the amount that was *actually* transferred
        uint256 balanceAfter = IERC20(_erc20).balanceOf(address(this));
        require(balanceAfter >= balanceBefore, 'VolmexPool: Token transfer overflow met');
        return balanceAfter - balanceBefore; // underflow already checked above, just subtract
    }
}

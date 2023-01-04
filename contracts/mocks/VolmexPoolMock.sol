// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.17;

import "../VolmexPool.sol";

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

        IEIP20NonStandard(_erc20).transferFrom(_from, address(this), _amount);

        uint256 balanceAfter = IERC20(_erc20).balanceOf(address(this));
        require(balanceAfter >= balanceBefore, "VolmexPool: Token transfer overflow met");
        return balanceAfter - balanceBefore;
    }
}

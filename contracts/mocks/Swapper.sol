// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.11;

import "../interfaces/IVolmexPoolView.sol";
import "../interfaces/IVolmexPool.sol";
import "../interfaces/IVolmexController.sol";
import "../interfaces/IERC20Modified.sol";

contract Swapper {
    struct TokenRecord {
        address self;
        uint256 balance;
        uint256 leverage;
        uint8 decimals;
        uint256 userBalance;
    }

    IVolmexPoolView public poolView;
    IVolmexController public controller;

    constructor(IVolmexPoolView _poolView, IVolmexController _controller) {
        poolView = _poolView;
        controller = _controller;
    }

    function doSwap(
        address _pool,
        address _tokenIn,
        uint256 _amountIn,
        address _tokenOut,
        uint256 _amountOut
    ) external {
        (IVolmexPoolView.TokenRecord memory recordPrimary, IVolmexPoolView.TokenRecord memory recordComp, , ) = poolView.getPoolInfo(_pool, msg.sender);

        IERC20Modified(_tokenIn).approve(address(controller), _amountIn);

        uint256 before = IERC20Modified(_tokenOut).balanceOf(address(this));
        controller.swap(0, _tokenIn, _amountIn, _tokenOut, _amountOut);

        (recordPrimary, recordComp, , ) = poolView.getPoolInfo(_pool, msg.sender);

        // Sync again
        IERC20Modified(_tokenIn).approve(address(controller), 10000000000000000000);
        before = IERC20Modified(_tokenOut).balanceOf(address(this));
        controller.swap(0, _tokenIn, 10000000000000000000, _tokenOut, 76916491032864410);
    }
}

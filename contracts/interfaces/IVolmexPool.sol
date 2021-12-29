// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.

// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.
// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.11;

import '@openzeppelin/contracts-upgradeable/utils/introspection/IERC165Upgradeable.sol';

import '../libs/tokens/Token.sol';
import './IVolmexProtocol.sol';
import './IVolmexRepricer.sol';
import './IVolmexController.sol';

interface IVolmexPool is IERC20, IERC165Upgradeable {
    function repricingBlock() external view returns (uint256);

    function baseFee() external view returns (uint256);

    function feeAmpPrimary() external view returns (uint256);

    function feeAmpComplement() external view returns (uint256);

    function maxFee() external view returns (uint256);

    function pMin() external view returns (uint256);

    function qMin() external view returns (uint256);

    function exposureLimitPrimary() external view returns (uint256);

    function exposureLimitComplement() external view returns (uint256);

    function protocol() external view returns (IVolmexProtocol);

    function repricer() external view returns (IVolmexRepricer);

    function isFinalized() external view returns (bool);

    function getTokens() external view returns (address[2] memory tokens);

    function getLeverage(address token) external view returns (uint256);

    function getBalance(address token) external view returns (uint256);

    function getPrimaryDerivativeAddress() external view returns (address);

    function volatilityIndex() external view returns (uint256);

    function getComplementDerivativeAddress() external view returns (address);

    function paused() external view returns (bool);

    function joinPool(uint256 poolAmountOut, uint256[2] calldata maxAmountsIn, address receiver) external;

    function exitPool(uint256 poolAmountIn, uint256[2] calldata minAmountsOut, address receiver) external;

    function swapExactAmountIn(
        address tokenIn,
        uint256 tokenAmountIn,
        address tokenOut,
        uint256 minAmountOut,
        address receiver,
        bool toController
    ) external returns (uint256 tokenAmountOut, uint256 spotPriceAfter);

    function setController(IVolmexController controller) external;

    function flashLoan(
        address receiverAddress,
        address assetToken,
        uint256 amount,
        bytes calldata params
    ) external;

    function getTokenAmountOut(
        address tokenIn,
        uint256 tokenAmountIn
    ) external view returns (uint256, uint256);

    function getTokensToJoin(uint256 poolAmountOut) external view returns (uint256[2] memory maxAmountsIn);

    function swapExactAmountOut(
        address tokenIn,
        uint256 maxAmountIn,
        address tokenOut,
        uint256 tokenAmountOut,
        address receiver,
        bool toController
    ) external returns (uint256 tokenAmountIn, uint256 spotPriceAfter);

    function getTokenAmountIn(
        address tokenOut,
        uint256 tokenAmountOut
    ) external view returns (uint256, uint256);
}

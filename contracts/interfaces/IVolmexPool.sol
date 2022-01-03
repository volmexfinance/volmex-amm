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

import '../libs/tokens/Token.sol';
import './IVolmexProtocol.sol';
import './IVolmexRepricer.sol';
import './IVolmexController.sol';

interface IVolmexPool is IERC20 {
    struct Record {
        uint256 leverage;
        uint256 balance;
    }

    event Swapped(
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 tokenAmountIn,
        uint256 tokenAmountOut,
        uint256 fee,
        uint256 tokenBalanceIn,
        uint256 tokenBalanceOut,
        uint256 tokenLeverageIn,
        uint256 tokenLeverageOut
    );
    event Joined(address indexed caller, address indexed tokenIn, uint256 tokenAmountIn);
    event Exited(address indexed caller, address indexed tokenOut, uint256 tokenAmountOut);
    event Repriced(
        uint256 repricingBlock,
        uint256 balancePrimary,
        uint256 balanceComplement,
        uint256 leveragePrimary,
        uint256 leverageComplement,
        uint256 newLeveragePrimary,
        uint256 newLeverageComplement,
        uint256 estPricePrimary,
        uint256 estPriceComplement
    );
    event Called(bytes4 indexed sig, address indexed caller, bytes data) anonymous;
    event Loaned(
        address indexed target,
        address indexed asset,
        uint256 amount,
        uint256 premium
    );
    event FlashLoanPremiumUpdated(uint256 premium);
    event ControllerSet(address indexed controller);
    event FeeParamsSet(
        uint256 baseFee,
        uint256 maxFee,
        uint256 feeAmpPrimary,
        uint256 feeAmpComplement
    );

    // Getter methods
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
    function volatilityIndex() external view returns (uint256);
    function finalized() external view returns (bool);
    function upperBoundary() external view returns (uint256);
    function adminFee() external view returns (uint256);
    function getLeverage(address _token) external view returns (uint256);
    function getBalance(address _token) external view returns (uint256);
    function tokens(uint256 _index) external view returns (address);
    function getTokensToJoin(uint256 _poolAmountOut) external view returns (uint256[2] memory);
    function getTokensToExit(uint256 _poolAmountIn) external view returns (uint256[2] memory);
    function flashLoanPremium() external view returns (uint256);
    function getLeveragedBalance(Record memory r) external pure returns (uint256);
    function getRepriced(address _tokenIn)
        external
        view
        returns (Record memory, Record memory);
    function getTokenAmountOut(
        address _tokenIn,
        uint256 _tokenAmountIn
    ) external view returns (uint256, uint256);
    function calcFee(
        Record memory _inRecord,
        uint256 _tokenAmountIn,
        Record memory _outRecord,
        uint256 _tokenAmountOut,
        uint256 _feeAmp
    ) external view returns (uint256 fee);

    // Setter methods
    function setController(IVolmexController _controller) external;
    function updateFlashLoanPremium(uint256 _premium) external;
    function joinPool(uint256 _poolAmountOut, uint256[2] calldata _maxAmountsIn, address _receiver) external;
    function exitPool(uint256 _poolAmountIn, uint256[2] calldata _minAmountsOut, address _receiver) external;
    function pause() external;
    function unpause() external;
    function reprice() external;
    function swapExactAmountIn(
        address _tokenIn,
        uint256 _tokenAmountIn,
        address _tokenOut,
        uint256 _minAmountOut,
        address _receiver,
        bool _toController
    ) external returns (uint256, uint256);
    function flashLoan(
        address _receiverAddress,
        address _assetToken,
        uint256 _amount,
        bytes calldata _params
    ) external;
    function finalize(
        uint256 _primaryBalance,
        uint256 _primaryLeverage,
        uint256 _complementBalance,
        uint256 _complementLeverage,
        uint256 _exposureLimitPrimary,
        uint256 _exposureLimitComplement,
        uint256 _pMin,
        uint256 _qMin
    ) external;
}

// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.11;

import "./IERC20Modified.sol";
import "./IVolmexPool.sol";
import "./IPausablePool.sol";
import "./IVolmexProtocol.sol";

interface IVolmexController {
    event AdminFeeUpdated(uint256 adminFee);
    event CollateralSwapped(
        uint256 volatilityAmountConsumed,
        uint256 collateralOutAmount,
        uint256 protocolFee,
        uint256 poolFee,
        uint256 indexed stableCoinIndex,
        address indexed token
    );
    event PoolSwapped(
        uint256 volatilityInAmount,
        uint256 volatilityOutAmount,
        uint256 protocolFee,
        uint256[2] poolFee,
        uint256 indexed stableCoinIndex,
        address[2] tokens
    );
    event PoolAdded(uint256 indexed poolIndex, address indexed pool);
    event StableCoinAdded(uint256 indexed stableCoinIndex, address indexed stableCoin);
    event ProtocolAdded(uint256 poolIndex, uint256 stableCoinIndex, address indexed protocol);
    event PoolTokensCollected(address indexed owner, uint256 amount);

    // Getter methods
    function stableCoinIndex() external view returns (uint256);
    function poolIndex() external view returns (uint256);
    function pools(uint256 _index) external view returns (IVolmexPool);
    function stableCoins(uint256 _index) external view returns (IERC20Modified);
    function isPool(address _pool) external view returns (bool);
    function precisionRatios(uint256 _index) external view returns (uint256);
    function protocols(
        uint256 _poolIndex,
        uint256 _stableCoinIndex
    ) external view returns (IVolmexProtocol);

    // Setter methods
    function addPool(IVolmexPool _pool) external;
    function addStableCoin(IERC20Modified _stableCoin) external;
    function togglePause(bool _isPause) external;
    function collect(IVolmexPool _pool) external;
    function addProtocol(
        uint256 _poolIndex,
        uint256 _stableCoinIndex,
        IVolmexProtocol _protocol
    ) external;
    function swapCollateralToVolatility(
        uint256[2] calldata _amounts,
        address _tokenOut,
        uint256[2] calldata _indices
    ) external;
    function swapVolatilityToCollateral(
        uint256[2] calldata _amounts,
        uint256[2] calldata _indices,
        IERC20Modified _tokenIn
    ) external;
    function swapBetweenPools(
        address[2] calldata _tokens,
        uint256[2] calldata _amounts,
        uint256[3] calldata _indices
    ) external;
    function addLiquidity(
        uint256 _poolAmountOut,
        uint256[2] calldata _maxAmountsIn,
        uint256 _poolIndex
    ) external;
    function removeLiquidity(
        uint256 _poolAmountIn,
        uint256[2] calldata _minAmountsOut,
        uint256 _poolIndex
    ) external;
    function swap(
        uint256 _poolIndex,
        address _tokenIn,
        uint256 _amountIn,
        address _tokenOut,
        uint256 _amountOut
    ) external;
    function transferAssetToPool(
        IERC20Modified _token,
        address _account,
        uint256 _amount
    ) external;
}
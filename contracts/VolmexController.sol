// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.4;

import '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';

import './interfaces/IVolmexAMM.sol';
import './interfaces/IVolmexProtocol.sol';
import './interfaces/IERC20Modified.sol';
import './interfaces/IVolmexOracle.sol';

/**
 * @title Volmex Controller contract
 * @author volmex.finance [security@volmexlabs.com]
 */
contract VolmexController is OwnableUpgradeable {
    event AdminFeeUpdated(uint256 adminFee);

    event AssetSwaped(uint256 assetInAmount, uint256 assetOutAmount);

    event SetPool(
        uint256 indexed poolIndex,
        address indexed pool
    );

    event SetStablecoin(
        uint256 indexed stablecoinIndex,
        address indexed stablecoin
    );

    event SetProtocol(
        uint256 poolIndex,
        uint256 stablecoinIndex,
        address indexed protocol
    );

    event UpdatedMinimumCollateral(uint256 newMinimumCollateralQty);

    // Ratio of volatility to be minted per 250 collateral
    uint256 private _volatilityCapRatio;
    // Minimum amount of collateral amount needed to collateralize
    uint256 private _minimumCollateralQty;
    // Used to set the index of stablecoin
    uint256 public stablecoinIndex;
    // Used to set the index of pool
    uint256 public poolIndex;

    // Store the addresses of pools
    mapping(uint256 => address) public pools;
    // Store the addresses of stablecoins
    /// @notice We have used IERC20Modified instead of IERC20, because the volatility tokens
    /// can't be typecasted to IERC20.
    /// Note: We have used the standard methods on IERC20 only.
    mapping(uint256 => IERC20Modified) public stablecoins;
    // Store the addresses of protocols { pool index => stablecoin index => protocol address }
    mapping(uint256 => mapping(uint256 => IVolmexProtocol)) public protocols;
    // Store the bool value of pools to confirm it is pool
    mapping(address => bool) public isPool;
    // Address of the oracle
    IVolmexOracle public oracle;
    // Value of token decimal precision 10^18
    uint256 private constant BONE = 1000000000000000000;

    /**
     * @notice Initializes the contract
     *
     * @dev Sets the volatilityCapRatio and _minimumCollateralQty
     *
     * @param _stablecoin Address of the collateral token used in protocol
     * @param _pool Address of the pool contract
     * @param _protocol Address of the protocol contract
     */
    function initialize(
        IERC20Modified _stablecoin,
        address _pool,
        IVolmexProtocol _protocol,
        IVolmexOracle _oracle
    ) external initializer {
        pools[poolIndex] = _pool;
        stablecoins[stablecoinIndex] = _stablecoin;
        protocols[poolIndex][stablecoinIndex] = _protocol;
        oracle = _oracle;

        isPool[_pool] = true;

        _volatilityCapRatio = _protocol.volatilityCapRatio();
        _minimumCollateralQty = _protocol.minimumCollateralQty();
    }

    /**
     * @notice Used to set the pool on new index
     *
     * @param _pool Address of the AMM contract
     */
    function setPool(address _pool) external onlyOwner {
        poolIndex++;
        pools[poolIndex] = _pool;

        emit SetPool(poolIndex, _pool);
    }

    /**
     * @notice Usesd to set the stablecoin on new index
     *
     * @param _stablecoin Address of the stablecoin
     */
    function setStablecoin(IERC20Modified _stablecoin) external onlyOwner {
        stablecoinIndex++;
        stablecoins[stablecoinIndex] = _stablecoin;

        emit SetStablecoin(stablecoinIndex, address(_stablecoin));
    }

    /**
     * @notice Used to set the protocol on a particular pool and stablecoin index
     *
     * @param _protocol Address of the Protocol contract
     */
    function setProtocol(
        uint256 _poolIndex,
        uint256 _stablecoinIndex,
        IVolmexProtocol _protocol
    ) external onlyOwner {
        protocols[_poolIndex][_stablecoinIndex] = _protocol;

        emit SetProtocol(_poolIndex, _stablecoinIndex, address(_protocol));
    }

    /**
     * @notice Used to update the minimum collateral qty value
     */
    function updateMinCollateralQty(uint256 _minCollateralQty) external onlyOwner {
        _minimumCollateralQty = _minCollateralQty;

        emit UpdatedMinimumCollateral(_minCollateralQty);
    }

    /**
     * @notice Used to swap collateral token to a type of volatility token
     *
     * @dev Amount if transferred to the controller and approved for pool
     * @dev collateralize the amount to get volatility
     * @dev Swaps half the quantity of volatility asset using pool contract
     * @dev Transfers the asset to caller
     *
     * @param _amount Amount of collateral token
     * @param _isInverseRequired Bool value token type required { true: iETHV, false: ETHV }
     */
    function swapCollateralToVolatility(
        uint256 _amount,
        bool _isInverseRequired,
        uint256 _poolIndex,
        uint256 _stablecoinIndex
    ) external {
        IVolmexProtocol _protocol = protocols[_poolIndex][_stablecoinIndex];
        IERC20Modified stablecoin = stablecoins[_stablecoinIndex];
        stablecoin.transferFrom(msg.sender, address(this), _amount);
        _approveAssets(stablecoin, _amount, address(this), address(_protocol));

        _protocol.collateralize(_amount);

        uint256 volatilityAmount = calculateAssetQuantity(_amount, _protocol.issuanceFees(), true);

        IERC20Modified volatilityToken = _protocol.volatilityToken();
        IERC20Modified inverseVolatilityToken = _protocol.inverseVolatilityToken();

        IVolmexAMM _pool = IVolmexAMM(pools[_poolIndex]);

        uint256 tokenAmountOut;
        if (_isInverseRequired) {
            _approveAssets(volatilityToken, volatilityAmount, address(this), address(_pool));
            tokenAmountOut = _swap(
                _pool,
                address(_protocol.volatilityToken()),
                volatilityAmount,
                address(_protocol.inverseVolatilityToken()),
                volatilityAmount >> 1,
                address(0)
            );
        } else {
            _approveAssets(inverseVolatilityToken, volatilityAmount, address(this), address(_pool));
            tokenAmountOut = _swap(
                _pool,
                address(_protocol.inverseVolatilityToken()),
                volatilityAmount,
                address(_protocol.volatilityToken()),
                volatilityAmount >> 1,
                address(0)
            );
        }

        uint256 totalVolatilityAmount = volatilityAmount + tokenAmountOut;
        transferAsset(
            _isInverseRequired ? inverseVolatilityToken : volatilityToken,
            totalVolatilityAmount
        );

        emit AssetSwaped(_amount, totalVolatilityAmount);
    }

    /**
     * @notice Used to swap a type of volatility token to collateral token
     *
     * @dev Amount if transferred to the controller and approved for pool
     * @dev Swaps half the quantity of volatility asset using pool contract
     * @dev redeems the amount to get collateral
     * @dev Transfers the asset to caller
     *
     * @param _amount Amount of volatility token
     * @param _isInverse Bool value of token type passed { true: iETHV, false: ETHV }
     */
    function swapVolatilityToCollateral(
        uint256 _amount,
        bool _isInverse,
        uint256 _poolIndex,
        uint256 _stablecoinIndex
    ) external {
        IVolmexProtocol _protocol = protocols[_poolIndex][_stablecoinIndex];
        IERC20Modified volatilityToken = _protocol.volatilityToken();
        IERC20Modified inverseVolatilityToken = _protocol.inverseVolatilityToken();

        IVolmexAMM _pool = IVolmexAMM(pools[_poolIndex]);

        uint256 tokenAmountOut;
        uint256 swapAmount;
        if (!_isInverse) {
            volatilityToken.transferFrom(msg.sender, address(this), _amount);
            _approveAssets(volatilityToken, _amount >> 1, address(this), address(_pool));

            (swapAmount, tokenAmountOut,,,) = _getSwappedAssetAmount(
                address(volatilityToken),
                _amount,
                _poolIndex,
                _stablecoinIndex,
                false
            );

            require(tokenAmountOut <= _amount - swapAmount, 'VolmexController: Amount out limit exploit');

            tokenAmountOut = _swap(
                _pool,
                address(volatilityToken),
                swapAmount,
                address(inverseVolatilityToken),
                tokenAmountOut,
                address(0)
            );
        } else {
            inverseVolatilityToken.transferFrom(msg.sender, address(this), _amount);
            _approveAssets(inverseVolatilityToken, _amount >> 1, address(this), address(_pool));

            (tokenAmountOut, ) = _pool.getTokenAmountOut(
                address(inverseVolatilityToken),
                _amount >> 1,
                address(volatilityToken)
            );

            tokenAmountOut = _swap(
                _pool,
                address(inverseVolatilityToken),
                _amount >> 1,
                address(volatilityToken),
                tokenAmountOut,
                address(0)
            );
        }

        uint256 collateralAmount = calculateAssetQuantity(
            tokenAmountOut * _volatilityCapRatio,
            _protocol.redeemFees(),
            false
        );

        _protocol.redeem(tokenAmountOut);

        IERC20Modified stablecoin = stablecoins[_stablecoinIndex];
        transferAsset(stablecoin, collateralAmount);
        transferAsset(
            _isInverse ? volatilityToken : inverseVolatilityToken,
            _amount - swapAmount - tokenAmountOut
        );

        emit AssetSwaped(_amount, collateralAmount);
    }

    function swapAssets(
        IERC20Modified _tokenIn,
        uint256 _amountIn,
        address _tokenOut,
        uint256 _tokenInPoolIndex,
        uint256 _tokenOutPoolIndex,
        uint256 _stablecoinIndex
    ) external {
        IVolmexAMM _pool = IVolmexAMM(pools[_tokenInPoolIndex]);
        _tokenIn.transferFrom(msg.sender, address(this), _amountIn);
        _approveAssets(_tokenIn, _amountIn, address(this), address(_pool));

        uint256 tokenAmount = _swap(
            _pool,
            address(_tokenIn),
            _amountIn >> 1,
            _pool.getPrimaryDerivativeAddress() == address(_tokenIn)
                ? _pool.getComplementDerivativeAddress()
                : _pool.getPrimaryDerivativeAddress(),
            _amountIn / 10,
            address(0)
        );

        IVolmexProtocol _protocol = protocols[_tokenInPoolIndex][_stablecoinIndex];
        _protocol.redeem(tokenAmount);

        uint256 _collateralAmount = calculateAssetQuantity(
            tokenAmount * _volatilityCapRatio,
            _protocol.redeemFees(),
            false
        );

        _protocol = protocols[_tokenOutPoolIndex][_stablecoinIndex];
        _protocol.collateralize(_collateralAmount);
        uint256 _volatilityAmount = calculateAssetQuantity(
            _collateralAmount,
            _protocol.issuanceFees(),
            true
        );

        _pool = IVolmexAMM(pools[_tokenOutPoolIndex]);
        uint256 tokenAmountOut = _swap(
            _pool,
            _pool.getPrimaryDerivativeAddress() == address(_tokenOut)
                ? _pool.getComplementDerivativeAddress()
                : _pool.getPrimaryDerivativeAddress(),
            _volatilityAmount >> 1,
            _tokenOut,
            _volatilityAmount / 10,
            address(0)
        );

        transferAsset(_tokenIn, (_amountIn >> 1) - tokenAmount);
        transferAsset(IERC20Modified(_tokenOut), tokenAmountOut);
    }

    /**
     * @notice Used to add liquidity in the pool
     *
     * @param _poolAmountOut Amount of pool token mint and transfer to LP
     * @param _maxAmountsIn Max amount of pool assets an LP can supply
     * @param _poolIndex Index of the pool in which user wants to add liquidity
     */
    function addLiquidity(
        uint256 _poolAmountOut,
        uint256[2] calldata _maxAmountsIn,
        uint256 _poolIndex
    ) external {
        IVolmexAMM _pool = IVolmexAMM(pools[_poolIndex]);

        _pool.joinPool(_poolAmountOut, _maxAmountsIn, msg.sender);
    }

    /**
     * @notice Used to remove liquidity from the pool
     *
     * @param _poolAmountIn Amount of pool token transfer to the pool
     * @param _minAmountsOut Min amount of pool assets an LP wish to redeem
     * @param _poolIndex Index of the pool in which user wants to add liquidity
     */
    function removeLiquidity(
        uint256 _poolAmountIn,
        uint256[2] calldata _minAmountsOut,
        uint256 _poolIndex
    ) external {
        IVolmexAMM _pool = IVolmexAMM(pools[_poolIndex]);

        _pool.exitPool(_poolAmountIn, _minAmountsOut, msg.sender);
    }

    /**
     * @notice Used to call flash loan on AMM
     *
     * @dev This method is for developers.
     * Make sure you call this metehod from a contract with the implementation
     * of IFlashLoanReceiver interface
     *
     * @param _assetToken Address of the token in need
     * @param _amount Amount of token in need
     * @param _params msg.data for verifying the loan
     * @param _poolIndex Index of the AMM
     */
    function makeFlashLoan(
        address _assetToken,
        uint256 _amount,
        bytes calldata _params,
        uint256 _poolIndex
    ) external {
        IVolmexAMM _pool = IVolmexAMM(pools[_poolIndex]);
        _pool.flashLoan(
            msg.sender,
            _assetToken,
            _amount,
            _params
        );
    }

    function swap(
        uint256 _poolIndex,
        address _tokenIn,
        uint256 _amountIn,
        address _tokenOut,
        uint256 _amountOut
    ) external {
        IVolmexAMM _amm = IVolmexAMM(pools[_poolIndex]);

        _swap(
            _amm,
            _tokenIn,
            _amountIn,
            _tokenOut,
            _amountOut,
            msg.sender
        );
    }

    //solium-disable-next-line security/no-assign-params
    function calculateAssetQuantity(
        uint256 _amount,
        uint256 _feePercent,
        bool isVolatility
    ) internal view returns (uint256) {
        uint256 fee = (_amount * _feePercent) / 10000;
        _amount = _amount - fee;

        return isVolatility ? _amount / _volatilityCapRatio : _amount;
    }

    function transferAsset(IERC20Modified _token, uint256 _amount) internal {
        _token.transfer(msg.sender, _amount);
    }

    function _swap(
        IVolmexAMM _pool,
        address _tokenIn,
        uint256 _amountIn,
        address _tokenOut,
        uint256 _amountOut,
        address receiver
    ) internal returns (uint256 exactTokenAmountOut) {
        (exactTokenAmountOut, ) = _pool.swapExactAmountIn(
            _tokenIn,
            _amountIn,
            _tokenOut,
            _amountOut,
            receiver
        );
    }

    function _approveAssets(
        IERC20Modified _token,
        uint256 _amount,
        address _owner,
        address _spender
    ) internal {
        uint256 _allowance = _token.allowance(_owner, _spender);

        if (_amount <= _allowance) return;

        _token.approve(_spender, _amount);
    }

    function transferAssetToPool(
        IERC20Modified _token,
        address _account,
        uint256 _amount
    ) external {
        require(isPool[msg.sender], 'VolmexController: Caller is not pool');
        _token.transferFrom(_account, msg.sender, _amount);
    }

    function volatilityAmountToSwap(
        uint256 _amount,
        uint256 _poolIndex,
        bool isInverse,
        uint256 fee
    ) internal view returns (uint256 volatilityAmount) {
        uint256 price = oracle.volatilityTokenPriceByIndex(_poolIndex);
        uint256 iPrice = (_volatilityCapRatio * 10000) - price;

        IVolmexAMM _pool = IVolmexAMM(pools[_poolIndex]);

        uint256 leverage = _pool.getLeverage(_pool.getPrimaryDerivativeAddress());
        uint256 iLeverage = _pool.getLeverage(_pool.getComplementDerivativeAddress());

        if (fee > 1) {
            volatilityAmount = ((_amount * iPrice * iLeverage) * BONE) / (price * leverage * fee + iPrice * iLeverage * BONE);
        } else {
            volatilityAmount = (_amount * iPrice * iLeverage) / ((price * leverage * fee) + iPrice * iLeverage);
        }
    }

    function getSwappedAssetAmount(
        address _tokenIn,
        uint256 _amount,
        uint256 _poolIndex,
        uint256 _stablecoinIndex,
        bool isInverse
    ) external view returns (uint256 collateralAmount, uint256 fee, uint256 leftOverAmount) {
        (,, collateralAmount, leftOverAmount, fee) = _getSwappedAssetAmount(
            _tokenIn,
            _amount,
            _poolIndex,
            _stablecoinIndex,
            isInverse
        );
    }

    function _getSwappedAssetAmount(
        address _tokenIn,
        uint256 _amount,
        uint256 _poolIndex,
        uint256 _stablecoinIndex,
        bool isInverse
    ) internal view returns (uint256 swapAmount, uint256 amountOut, uint256 collateralAmount, uint256 leftOverAmount, uint256 fee) {
        IVolmexProtocol _protocol = protocols[_poolIndex][_stablecoinIndex];
        IVolmexAMM _pool = IVolmexAMM(pools[_poolIndex]);

        swapAmount = volatilityAmountToSwap(_amount, _poolIndex, isInverse, 1);

        amountOut;
        (amountOut, fee) = _pool.getTokenAmountOut(
            _tokenIn,
            swapAmount,
            _pool.getPrimaryDerivativeAddress() == _tokenIn ?
                _pool.getComplementDerivativeAddress() : _pool.getPrimaryDerivativeAddress()
        );

        fee = BONE - fee;
        swapAmount = volatilityAmountToSwap(_amount, _poolIndex, isInverse, fee);

        (amountOut, fee) = _pool.getTokenAmountOut(
            _tokenIn,
            swapAmount,
            _pool.getPrimaryDerivativeAddress() == _tokenIn ?
                _pool.getComplementDerivativeAddress() : _pool.getPrimaryDerivativeAddress()
        );

        collateralAmount = calculateAssetQuantity(
            amountOut * _volatilityCapRatio,
            _protocol.redeemFees(),
            false
        );

        leftOverAmount = _amount - swapAmount - amountOut;
    }
}
/**
 * Indices for Pool, Stablecoin and Protocol mappings
 *
 * Pool { 0 = ETHV, 1 = BTCV }
 * Stablecoin { 0 = DAI, 1 = USDC }
 * Protocol { 0 = ETHV-DAI, 1 = ETHV-USDC, 2 = BTCV-DAI, 3 = BTCV-USDC }
 *
 * Pools          Stablecoin             Protocol
 *  0                 0                     0
 *  0                 1                     1
 *  1                 0                     2
 *  1                 1                     3
 */

// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.7.6;

import '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol';

import './interfaces/IVolmexAMM.sol';
import './interfaces/IVolmexProtocol.sol';
import './interfaces/IERC20Modified.sol';

/**
 * @title Volmex Controller contract
 * @author volmex.finance [security@volmexlabs.com]
 */
contract VolmexController is OwnableUpgradeable {
    using SafeMathUpgradeable for uint256;

    event AdminFeeUpdated(uint256 adminFee);

    event AssetSwaped(uint256 assetInAmount, uint256 assetOutAmount);

    // Address of the collateral used in protocol
    IERC20Modified public stablecoin;
    // Ratio of volatility to be minted per 250 collateral
    uint256 private _volatilityCapRatio;
    // Minimum amount of collateral amount needed to collateralize
    uint256 private _minimumCollateralQty;
    // Used to set the index of pool and protocol
    uint256 public poolIndex;

    // Store the addresses of pools
    mapping(uint256 => address) public pools;
    // Store the addresses of protocols
    mapping(uint256 => address) public protocols;

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
        IVolmexProtocol _protocol
    ) external initializer {
        stablecoin = _stablecoin;

        pools[poolIndex] = _pool;
        protocols[poolIndex] = address(_protocol);

        _volatilityCapRatio = _protocol.volatilityCapRatio();
        _minimumCollateralQty = _protocol.minimumCollateralQty();
    }

    /**
     * @notice Used to set the pool and protocol on new index
     */
    function setPoolAndProtocol(address _pool, address _protocol) external onlyOwner {
        poolIndex++;
        pools[poolIndex] = _pool;
        protocols[poolIndex] = address(_protocol);
    }

    /**
     * @notice Used to update the minimum collateral qty value
     */
    function updateMinCollateralQty(uint256 _minCollateralQty) external onlyOwner {
        _minimumCollateralQty = _minCollateralQty;
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
        uint256 _tokenPoolIndex
    ) external {
        IVolmexProtocol _protocol = IVolmexProtocol(protocols[_tokenPoolIndex]);
        stablecoin.transferFrom(msg.sender, address(this), _amount);
        _approveAssets(stablecoin, _amount, address(this), address(_protocol));

        _protocol.collateralize(_amount);

        uint256 volatilityAmount = calculateAssetQuantity(_amount, _protocol.issuanceFees(), true);

        IERC20Modified volatilityToken = _protocol.volatilityToken();
        IERC20Modified inverseVolatilityToken = _protocol.inverseVolatilityToken();

        IVolmexAMM _pool = IVolmexAMM(pools[_tokenPoolIndex]);

        uint256 tokenAmountOut;
        if (_isInverseRequired) {
            _approveAssets(volatilityToken, volatilityAmount, address(this), address(_pool));
            tokenAmountOut = _swap(
                _pool,
                address(_protocol.volatilityToken()),
                volatilityAmount,
                address(_protocol.inverseVolatilityToken()),
                volatilityAmount >> 1
            );
        } else {
            _approveAssets(inverseVolatilityToken, volatilityAmount, address(this), address(_pool));
            tokenAmountOut = _swap(
                _pool,
                address(_protocol.inverseVolatilityToken()),
                volatilityAmount,
                address(_protocol.volatilityToken()),
                volatilityAmount >> 1
            );
        }

        uint256 totalVolatilityAmount = volatilityAmount.add(tokenAmountOut);
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
        uint256 _tokenPoolIndex
    ) external {
        IVolmexProtocol _protocol = IVolmexProtocol(protocols[_tokenPoolIndex]);
        IERC20Modified volatilityToken = _protocol.volatilityToken();
        IERC20Modified inverseVolatilityToken = _protocol.inverseVolatilityToken();

        IVolmexAMM _pool = IVolmexAMM(pools[_tokenPoolIndex]);

        uint256 tokenAmountOut;
        if (_isInverse) {
            volatilityToken.transferFrom(msg.sender, address(this), _amount);
            _approveAssets(volatilityToken, _amount >> 1, address(this), address(_pool));

            tokenAmountOut = _swap(
                _pool,
                address(_protocol.volatilityToken()),
                _amount >> 1,
                address(_protocol.inverseVolatilityToken()),
                _amount.div(10)
            );
        } else {
            inverseVolatilityToken.transferFrom(msg.sender, address(this), _amount);
            _approveAssets(inverseVolatilityToken, _amount >> 1, address(this), address(_pool));

            tokenAmountOut = _swap(
                _pool,
                address(_protocol.inverseVolatilityToken()),
                _amount >> 1,
                address(_protocol.volatilityToken()),
                _amount.div(10)
            );
        }

        uint256 collateralAmount = calculateAssetQuantity(
            tokenAmountOut.mul(_volatilityCapRatio),
            _protocol.redeemFees(),
            false
        );

        _protocol.redeem(tokenAmountOut);

        transferAsset(stablecoin, collateralAmount);
        transferAsset(
            _isInverse ? volatilityToken : inverseVolatilityToken,
            (_amount >> 1).sub(tokenAmountOut)
        );

        emit AssetSwaped(_amount, collateralAmount);
    }

    function swapAssets(
        IERC20Modified _tokenIn,
        uint256 _amountIn,
        address _tokenOut,
        uint256 _tokenInPoolIndex,
        uint256 _tokenOutPoolIndex
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
            _amountIn.div(10)
        );

        IVolmexProtocol _protocol = IVolmexProtocol(protocols[_tokenInPoolIndex]);
        _protocol.redeem(tokenAmount);

        uint256 _collateralAmount = calculateAssetQuantity(
            tokenAmount.mul(_volatilityCapRatio),
            _protocol.redeemFees(),
            false
        );

        _protocol = IVolmexProtocol(protocols[_tokenOutPoolIndex]);
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
            _volatilityAmount.div(10)
        );

        transferAsset(_tokenIn, (_amountIn >> 1).sub(tokenAmount));
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
        IVolmexProtocol _protocol = IVolmexProtocol(protocols[_poolIndex]);

        _approveAssets(_protocol.volatilityToken(), _maxAmountsIn[0], msg.sender, address(_pool));
        _approveAssets(_protocol.inverseVolatilityToken(), _maxAmountsIn[1], msg.sender, address(_pool));

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
     * @notice Used to call falsh loan on AMM
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

    //solium-disable-next-line security/no-assign-params
    function calculateAssetQuantity(
        uint256 _amount,
        uint256 _feePercent,
        bool isVolatility
    ) internal view returns (uint256) {
        uint256 fee = (_amount.mul(_feePercent)).div(10000);
        _amount = _amount.sub(fee);

        return isVolatility ? _amount.div(_volatilityCapRatio) : _amount;
    }

    function transferAsset(IERC20Modified _token, uint256 _amount) internal {
        _token.transfer(msg.sender, _amount);
    }

    function _swap(
        IVolmexAMM _pool,
        address _tokenIn,
        uint256 _amountIn,
        address _tokenOut,
        uint256 _amountOut
    ) internal returns (uint256 exactTokenAmountOut) {
        (exactTokenAmountOut, ) = _pool.swapExactAmountIn(
            _tokenIn,
            _amountIn,
            _tokenOut,
            _amountOut
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
}

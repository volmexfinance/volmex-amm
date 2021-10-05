// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.7.6;

import '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';

import './IPool.sol';
import './interfaces/IVolmexProtocol.sol';
import './interfaces/IERC20Modified.sol';

/**
 * @title Volmex Controller contract
 * @author volmex.finance [security@volmexlabs.com]
 */
contract Controller is OwnableUpgradeable {
    event AdminFeeUpdated(uint256 adminFee);

    event AssetSwaped(uint256 assetInAmount, uint256 assetOutAmount);

    // Address of the collateral used in protocol
    IERC20Modified public stablecoin;
    // Address on the pool contract
    IPool public pool;
    // Address of the protocol contract
    IVolmexProtocol public protocol;
    // Ratio of volatility to be minted per 250 collateral
    uint256 private _volatilityCapRatio;
    // Minimum amount of collateral amount needed to collateralize
    uint256 private _minimumCollateralQty;

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
        IPool _pool,
        IVolmexProtocol _protocol
    ) external initializer {
        stablecoin = _stablecoin;
        pool = _pool;
        protocol = _protocol;

        _volatilityCapRatio = protocol.volatilityCapRatio();
        _minimumCollateralQty = protocol.minimumCollateralQty();
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
    function swapCollateralToVolatility(uint256 _amount, bool _isInverseRequired) external {
        stablecoin.transferFrom(msg.sender, address(this), _amount);
        stablecoin.approve(address(protocol), _amount);

        protocol.collateralize(_amount);

        uint256 volatilityAmount = calculateAssetQuantity(_amount, protocol.issuanceFees(), true);

        IERC20Modified volatilityToken = protocol.volatilityToken();
        IERC20Modified inverseVolatilityToken = protocol.inverseVolatilityToken();

        uint256 tokenAmountOut;
        if (_isInverseRequired) {
            volatilityToken.approve(address(pool), volatilityAmount);
            (tokenAmountOut, ) = pool.swapExactAmountIn(
                address(protocol.volatilityToken()),
                volatilityAmount,
                address(protocol.inverseVolatilityToken()),
                volatilityAmount / 2
            );
        } else {
            inverseVolatilityToken.approve(address(pool), volatilityAmount);
            (tokenAmountOut, ) = pool.swapExactAmountIn(
                address(protocol.inverseVolatilityToken()),
                volatilityAmount,
                address(protocol.volatilityToken()),
                volatilityAmount / 2
            );
        }

        transferAsset(
            _isInverseRequired ? inverseVolatilityToken : volatilityToken,
            volatilityAmount + tokenAmountOut
        );

        emit AssetSwaped(_amount, volatilityAmount + tokenAmountOut);
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
     * @param _isInverseRequired Bool value token type required { true: iETHV, false: ETHV }
     */
    function swapVolatilityToCollateral(uint256 _amount, bool _isInverseRequired) external {
        IERC20Modified volatilityToken = protocol.volatilityToken();
        IERC20Modified inverseVolatilityToken = protocol.inverseVolatilityToken();

        uint256 tokenAmountOut;
        if (_isInverseRequired) {
            volatilityToken.transferFrom(msg.sender, address(this), _amount);
            volatilityToken.approve(address(pool), _amount / 2);

            (tokenAmountOut, ) = pool.swapExactAmountIn(
                address(protocol.volatilityToken()),
                _amount / 2,
                address(protocol.inverseVolatilityToken()),
                _amount / 10
            );
        } else {
            inverseVolatilityToken.transferFrom(msg.sender, address(this), _amount);
            inverseVolatilityToken.approve(address(pool), _amount / 2);

            (tokenAmountOut, ) = pool.swapExactAmountIn(
                address(protocol.inverseVolatilityToken()),
                _amount / 2,
                address(protocol.volatilityToken()),
                _amount / 10
            );
        }

        uint256 collateralAmount = calculateAssetQuantity(
            tokenAmountOut * _volatilityCapRatio,
            protocol.redeemFees(),
            false
        );

        protocol.redeem(tokenAmountOut);

        transferAsset(stablecoin, collateralAmount);
        transferAsset(
            _isInverseRequired ? volatilityToken : inverseVolatilityToken,
            (_amount / 2) - tokenAmountOut
        );

        emit AssetSwaped(_amount, collateralAmount);
    }

    //solium-disable-next-line
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
}

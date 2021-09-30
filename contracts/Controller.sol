// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.7.6;

import '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';

import './IPool.sol';
import './interfaces/IVolmexProtocol.sol';
import './interfaces/IERC20Modified.sol';

contract Controller is OwnableUpgradeable {
    event AdminFeeUpdated(uint256 adminFee);

    event AssetSwaped(uint256 stablecoinQuantity, uint256 volatilityTokenOut);

    IERC20Modified public stablecoin;
    IPool public pool;
    IVolmexProtocol public protocol;
    uint256 private _volatilityCapRatio;
    uint256 private _minimumCollateralQty;

    uint256 public adminFee;
    uint256 public constant MAX_FEE = 100;

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

        adminFee = 10;
    }

    function updateAdminFee(uint256 _adminFee) external onlyOwner {
        require(_adminFee <= MAX_FEE, 'Controller: _adminFee OUT_OF_RANGE');
        adminFee = _adminFee;

        emit AdminFeeUpdated(_adminFee);
    }

    function swapCollateralToVolatility(uint256 _amount) external {
        stablecoin.transferFrom(msg.sender, address(this), _amount);
        stablecoin.approve(address(protocol), _amount);

        protocol.collateralize(_amount);

        uint256 volatilityAmount = calculateAssetQuantity(_amount, protocol.issuanceFees(), true);

        IERC20Modified volatilityToken = protocol.volatilityToken();
        IERC20Modified inverseVolatilityToken = protocol.inverseVolatilityToken();
        inverseVolatilityToken.approve(address(pool), volatilityAmount);
        uint256 tokenAmountOut;
        (tokenAmountOut, ) = pool.swapExactAmountIn(
            address(protocol.inverseVolatilityToken()),
            volatilityAmount,
            address(protocol.volatilityToken()),
            volatilityAmount / 2
        );

        transferAsset(volatilityToken, volatilityAmount + tokenAmountOut);

        emit AssetSwaped(_amount, volatilityAmount + tokenAmountOut);
    }

    function swapVolatilityToCollateral(uint256 _amount) external {
        IERC20Modified volatilityToken = protocol.volatilityToken();
        IERC20Modified inverseVolatilityToken = protocol.inverseVolatilityToken();

        volatilityToken.transferFrom(msg.sender, address(this), _amount);

        volatilityToken.approve(address(pool), _amount / 2);

        uint256 tokenAmountOut;
        (tokenAmountOut, ) = pool.swapExactAmountIn(
            address(protocol.volatilityToken()),
            _amount / 2,
            address(protocol.inverseVolatilityToken()),
            _amount / 3
        );

        uint256 collateralAmount = calculateAssetQuantity(
            tokenAmountOut * _volatilityCapRatio,
            protocol.redeemFees(),
            false
        );

        protocol.redeem(tokenAmountOut);

        transferAsset(stablecoin, collateralAmount);
        transferAsset(volatilityToken, (_amount / 2) - tokenAmountOut);

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

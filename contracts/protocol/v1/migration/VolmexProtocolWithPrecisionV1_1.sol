// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.17;

import "../VolmexProtocolWithPrecisionV1.sol";
import "./Migration.sol";

contract VolmexProtocolWithPrecisionV1_1 is VolmexProtocolWithPrecisionV1, Migration {
    /**
     * @notice Used to set the V2 protocol
     *
     * @param _v2Protocol Address of the V2 protocol
     */
    function setV2Protocol(
        IVolmexProtocol _v2Protocol,
        bool isSettling,
        uint256 _settlementPrice
    ) external virtual onlyOwner {
        v2Protocol = _v2Protocol;
        if(isSettling) {
            settle(_settlementPrice);
        }
        emit NewProtocolSet(address(_v2Protocol));
    }

    /**
     * @notice Used to migrate to V2 protocol
     *
     * @param _volatilityTokenAmount Amount of tokens that needs to migrate
     *
     */
    function migrateToV2(uint256 _volatilityTokenAmount)
        external
        virtual
        onlyActive
        onlySettled
    {
        require(_volatilityTokenAmount != 0, "Volmex: amount should be non-zero");
        (uint256 collQtyToBeRedeemed,) = redeemSettled(_volatilityTokenAmount, _volatilityTokenAmount, address(this));
        collateral.approve(address(v2Protocol), collQtyToBeRedeemed);
        (uint256 volatilityAmount,) = v2Protocol.collateralize(collQtyToBeRedeemed);

        IERC20Modified _volatilityToken = v2Protocol.volatilityToken();
        IERC20Modified _inverseVolatilityToken = v2Protocol.inverseVolatilityToken();

        _volatilityToken.transfer(msg.sender, volatilityAmount);
        _inverseVolatilityToken.transfer(msg.sender, volatilityAmount);
    }
}

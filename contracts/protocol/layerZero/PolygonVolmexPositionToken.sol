// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.17;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

import "contracts/helpers/ProxyOFTUpgradeable.sol";
import "contracts/interfaces/IERC20Modified.sol";

contract PolygonVolmexPositionToken is ProxyOFTUpgradeable, ERC20Upgradeable {
    IERC20Modified public volmexPositionToken;

    function initialize(address _volmexPositionToken, address _endPoint)
        external
        initializer
    {
        __ProxyOFTUpgradeable_init(_endPoint, address(_volmexPositionToken));
        volmexPositionToken = IERC20Modified(_volmexPositionToken);
    }

    // to handle tokens being sent on the source
    function _debitFrom(
        address _from,
        uint16,
        bytes memory,
        uint256 _amount
    ) internal override returns (uint256) {
        address spender = _msgSender();
        if (_from != spender) _spendAllowance(_from, spender, _amount);
        volmexPositionToken.burn(_from, _amount);
        return _amount;
    }

    // you can handle tokens being received on the destination
    function _creditTo(
        uint16,
        address _toAddress,
        uint256 _amount
    ) internal override {
        volmexPositionToken.mint(_toAddress, _amount);
    }
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PausableUpgradeable.sol";
import "@layerzerolabs/solidity-examples/contracts/contracts-upgradable/token/OFT/OFTCoreUpgradeable.sol";
import "../../helpers/ProxyOFTUpgradeable.sol";
import "../../interfaces/IVolmexPositionToken.sol";
import "hardhat/console.sol";

contract PolygonVolmexPositionToken is ProxyOFTUpgradeable, ERC20Upgradeable {

    IVolmexPositionToken public volmexPositionToken;

    function initialize(IVolmexPositionToken _volmexPositionToken, address _endPoint) external initializer
    {
        __ProxyOFTUpgradeable_init(_endPoint, address(_volmexPositionToken));
        volmexPositionToken = _volmexPositionToken;
    }

    // to handle tokens being sent on the source
    function _debitFrom(address _from, uint16 _dstChainId, bytes memory _toAddress, uint _amount) 
    internal 
    override 
    returns(uint) {
        console.log("Called _debitFrom");
        address spender = _msgSender();
        if (_from != spender) _spendAllowance(_from, spender, _amount);
        volmexPositionToken.burn(_from, _amount);
        return _amount;
    }

    // you can handle tokens being received on the destination
    function _creditTo(uint16 _srcChainId, address _toAddress, uint _amount) internal override {
        console.log("Called _creditTo");
        volmexPositionToken.mint(_toAddress, _amount);
    }
}

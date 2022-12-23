// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

import "@layerzerolabs/solidity-examples/contracts/contracts-upgradable/token/OFT/OFTCoreUpgradeable.sol";
import "@layerzerolabs/solidity-examples/contracts/contracts-upgradable/token/OFT/IOFTUpgradeable.sol";
import "../VolmexPositionToken.sol";
import "hardhat/console.sol";

contract Layer2VolmexPositionToken is OFTCoreUpgradeable, IOFTUpgradeable, VolmexPositionToken {
    
    function __Layer2VolmexPositionToken_init(string memory _name, string memory _symbol, address _lzEndpoint) 
    external 
    initializer {
        initialize(_name, _symbol);
        __OFTCoreUpgradeable_init(_lzEndpoint);
        __Ownable_init();
    }

    function circulatingSupply() external view returns (uint) {
        return totalSupply();
    }

    function supportsInterface(bytes4 interfaceId) 
    public 
    view 
    virtual 
    override(OFTCoreUpgradeable, IERC165Upgradeable, AccessControlUpgradeable) 
    returns (bool) {
        return 
        interfaceId == type(IOFTUpgradeable).interfaceId || 
        interfaceId == type(IERC165Upgradeable).interfaceId || 
        interfaceId == type(AccessControlUpgradeable).interfaceId || super.supportsInterface(interfaceId);
    }
    
    function _debitFrom(address _from, uint16 _dstChainId, bytes memory _toAddress, uint _amount) 
    internal 
    override 
    returns(uint) {
        console.log("Called _debitFrom");
        address spender = _msgSender();
        if (_from != spender) _spendAllowance(_from, spender, _amount);
        burn(_from, _amount);
        return _amount;
    }

    function _creditTo(uint16 _srcChainId, address _toAddress, uint _amount) internal override {
        console.log("Called _debitFrom");
        mint(_toAddress, _amount);
    }
}

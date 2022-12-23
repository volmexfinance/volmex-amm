// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import "@layerzerolabs/solidity-examples/contracts/contracts-upgradable/token/OFT/OFTCoreUpgradeable.sol";
import "@layerzerolabs/solidity-examples/contracts/contracts-upgradable/token/OFT/IOFTUpgradeable.sol";
import "contracts/protocol/VolmexPositionToken.sol";
import "hardhat/console.sol";

contract Layer1VolmexPositionToken is OFTCoreUpgradeable, IOFTUpgradeable, VolmexPositionToken {

    mapping(address => uint256) internal _lockedTokens;
    
    function __Layer1VolmexPositionToken_init(string memory _name, string memory _symbol, address _lzEndpoint) 
    external 
    initializer {
        initialize(_name, _symbol);
        __OFTCoreUpgradeable_init(_lzEndpoint);
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
        return interfaceId == type(IOFTUpgradeable).interfaceId || interfaceId == type(IERC20Upgradeable).interfaceId || super.supportsInterface(interfaceId);
    }
    
    function _debitFrom(address _from, uint16 _dstChainId, bytes memory _toAddress, uint _amount) 
    internal 
    override 
    returns(uint) {
        console.log("Called _debitFrom");
        if (_from != address(this)) _spendAllowance(_from, address(this), _amount);
        // locking tokens
        transferFrom(_from, address(this), _amount);
        _lockedTokens[_from] += _amount;
        return _lockedTokens[_from];
    }

    function _creditTo(uint16 _srcChainId, address _toAddress, uint _amount) internal override {
        console.log("Called _debitFrom");
        if (_lockedTokens[_toAddress] >= _amount) {
            _lockedTokens[_toAddress] -= _amount;
        } else {
            uint256 _currentBalance = _lockedTokens[_toAddress];
            delete(_lockedTokens[_toAddress]);
            mint(_toAddress, _amount - _currentBalance);
        }
    }
}

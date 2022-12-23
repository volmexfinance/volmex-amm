// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import "@layerzerolabs/solidity-examples/contracts/contracts-upgradable/token/OFT/OFTCoreUpgradeable.sol";
import "@layerzerolabs/solidity-examples/contracts/contracts-upgradable/token/OFT/IOFTUpgradeable.sol";
import "contracts/protocol/VolmexPositionToken.sol";

contract Layer1VolmexPositionToken is OFTCoreUpgradeable, VolmexPositionToken {
    mapping(address => uint256) internal _lockedTokens;

    function __Layer1VolmexPositionToken_init(
        string memory _name,
        string memory _symbol,
        address _lzEndpoint
    ) external initializer {
        // VolmexPositionToken associated initialize
        initialize(_name, _symbol);
        __OFTCoreUpgradeable_init(_lzEndpoint);
        __Ownable_init();
    }

    function circulatingSupply() external view returns (uint256) {
        return totalSupply();
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(OFTCoreUpgradeable, AccessControlUpgradeable)
        returns (bool)
    {
        return
            interfaceId == type(IOFTUpgradeable).interfaceId ||
            interfaceId == type(IERC165Upgradeable).interfaceId ||
            interfaceId == type(AccessControlUpgradeable).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    function _debitFrom(
        address _from,
        uint16 _dstChainId,
        bytes memory _toAddress,
        uint256 _amount
    ) internal override returns (uint256) {
        if (_from != address(this)) _spendAllowance(_from, address(this), _amount);
        // locking tokens
        _transfer(_from, address(this), _amount);
        _lockedTokens[_from] += _amount;
        return _lockedTokens[_from];
    }

    function _creditTo(
        uint16 _srcChainId,
        address _toAddress,
        uint256 _amount
    ) internal override {
        if (_lockedTokens[_toAddress] >= _amount) {
            _lockedTokens[_toAddress] -= _amount;
            _transfer(address(this), _toAddress, _amount);
        } else {
            uint256 _currentBalance = _lockedTokens[_toAddress];
            delete (_lockedTokens[_toAddress]);
            _mint(_toAddress, _amount - _currentBalance);
        }
    }
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import "@layerzerolabs/solidity-examples/contracts/contracts-upgradable/token/OFT/OFTCoreUpgradeable.sol";
import "@layerzerolabs/solidity-examples/contracts/contracts-upgradable/token/OFT/IOFTUpgradeable.sol";
import "contracts/protocol/VolmexPositionToken.sol";
import "contracts/interfaces/ILayerZeroVolmexPositionToken.sol";

contract Layer1VolmexPositionToken is OFTCoreUpgradeable, VolmexPositionToken, ILayerZeroVolmexPositionToken {
    mapping(address => uint256) internal _lockedTokens;

    // Adding a common init in Layer1VolmexPositionToken & Layer2VolmexPositionToken
    // so that Factory doesn't require if-else check
    function __LayerZero_init(
        string memory _name,
        string memory _symbol,
        address _lzEndpoint
    ) external initializer {
        __AccessControl_init_unchained();

        __ERC20Pausable_init();
        _vivName = _name;
        _vivSymbol = _symbol;

        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(VOLMEX_PROTOCOL_ROLE, msg.sender);

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
        uint16,
        bytes memory,
        uint256 _amount
    ) internal override returns (uint256) {
        address spender = _msgSender();
        if (_from != spender) _spendAllowance(_from, spender, _amount);
        _transfer(_from, address(this), _amount);
        _lockedTokens[_from] += _amount;
        return _amount;
    }

    function _creditTo(
        uint16,
        address _toAddress,
        uint256 _amount
    ) internal override {
        uint256 lockedTokens = _lockedTokens[_toAddress];
        if (_amount <= lockedTokens) {
            _lockedTokens[_toAddress] -= _amount;
            _transfer(address(this), _toAddress, _amount);
        } else {
            delete (_lockedTokens[_toAddress]);
            _transfer(address(this), _toAddress, lockedTokens);
            _mint(_toAddress, _amount - lockedTokens);
        }
    }
}

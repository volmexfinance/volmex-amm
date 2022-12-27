// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

import "@layerzerolabs/solidity-examples/contracts/contracts-upgradable/token/OFT/OFTCoreUpgradeable.sol";
import "@layerzerolabs/solidity-examples/contracts/contracts-upgradable/token/OFT/IOFTUpgradeable.sol";
import "../VolmexPositionToken.sol";
import "contracts/interfaces/ILayerZeroVolmexPositionToken.sol";

contract Layer2VolmexPositionToken is OFTCoreUpgradeable, IOFTUpgradeable, VolmexPositionToken, ILayerZeroVolmexPositionToken {
    // Adding a common init in Layer1VolmexPositionToken & Layer2VolmexPositionToken
    // so that Factory doesn't require if-else check
    function __LayerZero_init(
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
        override(OFTCoreUpgradeable, IERC165Upgradeable, AccessControlUpgradeable)
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
        _burn(_from, _amount);
        return _amount;
    }

    function _creditTo(
        uint16,
        address _toAddress,
        uint256 _amount
    ) internal override {
        _mint(_toAddress, _amount);
    }
}

/* // SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

import "@layerzerolabs/solidity-examples/contracts/contracts-upgradable/token/OFT/OFTCoreUpgradeable.sol";
import "../VolmexPositionToken.sol";

contract Layer2VolmexPositionToken is OFTCoreUpgradeable, VolmexPositionToken {
    function __Layer2VolmexPositionToken_init(
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
        uint16 _dstChainId,
        bytes memory _toAddress,
        uint256 _amount
    ) internal override returns (uint256) {
        address spender = _msgSender();
        if (_from != spender) _spendAllowance(_from, spender, _amount);
        _burn(_from, _amount);
        return _amount;
    }

    function _creditTo(
        uint16 _srcChainId,
        address _toAddress,
        uint256 _amount
    ) internal override {
        _mint(_toAddress, _amount);
    }
}
 */
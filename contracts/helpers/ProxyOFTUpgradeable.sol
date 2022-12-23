// SPDX-License-Identifier: MIT

pragma solidity =0.8.17;

import "@layerzerolabs/solidity-examples/contracts/contracts-upgradable/token/OFT/OFTCoreUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

contract ProxyOFTUpgradeable is OFTCoreUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    IERC20Upgradeable internal innerToken;

    function __ProxyOFTUpgradeable_init(address _lzEndpoint, address _token) onlyInitializing internal {
        innerToken = IERC20Upgradeable(_token);
        __OFTCoreUpgradeable_init_unchained(_lzEndpoint);
    }

    function circulatingSupply() public view virtual override returns (uint) {
        unchecked {
            return innerToken.totalSupply() - innerToken.balanceOf(address(this));
        }
    }

    function token() public view virtual returns (address) {
        return address(innerToken);
    }

    function _debitFrom(address _from, uint16, bytes memory, uint _amount) internal virtual override returns(uint) {
        require(_from == _msgSender(), "ProxyOFT: owner is not send caller");
        uint before = innerToken.balanceOf(address(this));
        innerToken.safeTransferFrom(_from, address(this), _amount);
        return innerToken.balanceOf(address(this)) - before;
    }

    function _creditTo(uint16, address _toAddress, uint _amount) internal virtual override {
        // uint before = innerToken.balanceOf(_toAddress);
        innerToken.safeTransfer(_toAddress, _amount);
        // uint creditedAmount = innerToken.balanceOf(_toAddress) - before;
    }
}

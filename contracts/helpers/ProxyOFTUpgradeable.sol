// SPDX-License-Identifier: MIT

pragma solidity =0.8.17;

import "@layerzerolabs/solidity-examples/contracts/contracts-upgradable/token/OFT/OFTCoreUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

abstract contract ProxyOFTUpgradeable is OFTCoreUpgradeable {
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
}

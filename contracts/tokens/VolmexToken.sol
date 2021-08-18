// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.7.6;

import "@openzeppelin/contracts-upgradeable/proxy/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20PausableUpgradeable.sol";

/**
 * @title Volmex Token Contract
 * @author volmex.finance [security@volmexlabs.com]
 *
 * Governance token contract of Volmex
 */
contract VolmexToken is
    Initializable,
    AccessControlUpgradeable,
    ERC20PausableUpgradeable
{
    /**
     * @dev Grants `DEFAULT_ADMIN_ROLE` to the
     * account that deploys the contract.
     *
     * See {ERC20-constructor}.
     */
    function initialize(string memory name, string memory symbol)
        external
        initializer
    {
        __ERC20_init_unchained(name, symbol);
        __AccessControl_init_unchained();

        __ERC20Pausable_init();

        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /**
     * @dev Creates `amount` new tokens for `to`.
     *
     * See {ERC20-_mint}.
     *
     */
    function mint(address to, uint256 amount) external virtual {
        _mint(to, amount);
    }

    /**
     * @dev Destroys `amount` tokens from the caller.
     *
     * See {ERC20-_burn}.
     */
    function burn(address from, uint256 amount) external virtual {
        _burn(from, amount);
    }

    /**
     * @dev Pauses all token transfers.
     *
     * See {ERC20Pausable} and {Pausable-_pause}.
     *
     */
    function pause() external virtual {
        _pause();
    }

    /**
     * @dev Unpauses all token transfers.
     *
     * See {ERC20Pausable} and {Pausable-_unpause}.
     *
     */
    function unpause() external virtual {
        _unpause();
    }
}

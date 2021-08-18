// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.7.6;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PausableUpgradeable.sol";

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
{}
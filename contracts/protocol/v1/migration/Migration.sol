// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.17;

import "../../../interfaces/IVolmexProtocol.sol";

/**
 * @title Migration contract
 * @author volmex.finance [security@volmexlabs.com]
 *
 * This protocol is used to migrate V1 tokens to V2
 */
contract Migration {
    // Address of V2 protocol
    IVolmexProtocol public v2Protocol;
}

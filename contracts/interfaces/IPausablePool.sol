// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.11;

interface IPausablePool {
    // Getter method
    function paused() external view returns (bool);

    // Setter methods
    function pause() external;
    function unpause() external;
}

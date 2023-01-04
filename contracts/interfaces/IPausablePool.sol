// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.17;

interface IPausablePool {
    // Getter method
    function paused() external view returns (bool);

    // Setter methods
    function pause() external;
    function unpause() external;
}

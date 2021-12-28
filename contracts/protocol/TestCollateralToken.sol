// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.11;

import "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";

contract TestCollateralToken is ERC20PresetMinterPauser {
    constructor(string memory symbol) ERC20PresetMinterPauser("VolmexTestCollateralToken", symbol) {
        mint(msg.sender, 100000000000000000000000000000000);
    }
}

// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.7.6;

import "@openzeppelin/contracts/presets/ERC20PresetMinterPauser.sol";

contract TestCollateralToken is ERC20PresetMinterPauser {
    constructor() ERC20PresetMinterPauser("VolmexTestCollateralToken", "VUSD") {
        mint(msg.sender, 10000000000000000000000);
    }
}

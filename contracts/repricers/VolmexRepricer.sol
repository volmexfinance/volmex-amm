// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.11;

import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165StorageUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/introspection/IERC165Upgradeable.sol";

import "../interfaces/IVolmexOracle.sol";
import "../interfaces/IVolmexRepricer.sol";
import "../maths/NumExtra.sol";

/**
 * @title Volmex Repricer contract
 * @author volmex.finance [security@volmexlabs.com]
 */
contract VolmexRepricer is ERC165StorageUpgradeable, NumExtra, IVolmexRepricer {
    // Interface ID of VolmexOracle contract, hashId = 0xf9fffc9f
    bytes4 private constant _IVOLMEX_ORACLE_ID = type(IVolmexOracle).interfaceId;
    // Interface ID of VolmexRepricer contract, hashId = 0x822da258
    bytes4 private constant _IVOLMEX_REPRICER_ID = type(IVolmexRepricer).interfaceId;

    // Instance of oracle contract
    IVolmexOracle public oracle;

    /**
     * @notice Initializes the contract, setting the required state variables
     * @param _oracle Address of the Volmex Oracle contract
     */
    function initialize(IVolmexOracle _oracle) external initializer {
        require(
            IERC165Upgradeable(address(_oracle)).supportsInterface(_IVOLMEX_ORACLE_ID),
            "VolmexController: Oracle does not supports interface"
        );
        oracle = _oracle;

        __ERC165Storage_init();
        _registerInterface(_IVOLMEX_REPRICER_ID);
    }

    /**
     * @notice Fetches the price of asset from oracle
     * @dev Calculates the price of complement asset. { volatility cap ratio - primary asset price }
     * @param _volatilityIndex Number value of the volatility index. { eg. 0 }
     */
    function reprice(uint256 _volatilityIndex)
        external
        view
        returns (
            uint256 estPrimaryPrice,
            uint256 estComplementPrice,
            uint256 estPrice
        )
    {
        (estPrimaryPrice, estComplementPrice) = oracle.getVolatilityTokenPriceByIndex(
            _volatilityIndex
        );
        estPrice = (estComplementPrice * BONE) / estPrimaryPrice;
    }

    /**
     * @notice Used to calculate the square root of the provided value
     * @param x Value of which the square root will be calculated
     */
    function sqrtWrapped(int256 x) external pure returns (int256) {
        return sqrt(x);
    }

    uint256[10] private __gap;
}

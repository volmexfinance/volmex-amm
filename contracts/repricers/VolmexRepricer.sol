// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.11;

import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165StorageUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/introspection/IERC165Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "../interfaces/IVolmexOracle.sol";
import "../interfaces/IVolmexRepricer.sol";
import "../maths/NumExtra.sol";

/**
 * @title Volmex Repricer contract
 * @author volmex.finance [security@volmexlabs.com]
 */
contract VolmexRepricer is
    OwnableUpgradeable,
    ERC165StorageUpgradeable,
    NumExtra,
    IVolmexRepricer
{
    // Interface ID of VolmexOracle contract, hashId = 0xf9fffc9f
    bytes4 private constant _IVOLMEX_ORACLE_ID = type(IVolmexOracle).interfaceId;
    // Interface ID of VolmexRepricer contract, hashId = 0x822da258
    bytes4 private constant _IVOLMEX_REPRICER_ID = type(IVolmexRepricer).interfaceId;

    // Instance of oracle contract
    IVolmexOracle public oracle;
    // Max stale price duration
    uint256 public allowedDelay;

    /**
     * @notice Initializes the contract, setting the required state variables
     * @param _oracle Address of the Volmex Oracle contract
     */
    function initialize(IVolmexOracle _oracle, address _owner) external initializer {
        require(
            IERC165Upgradeable(address(_oracle)).supportsInterface(_IVOLMEX_ORACLE_ID),
            "VolmexController: Oracle does not supports interface"
        );
        oracle = _oracle;
        allowedDelay = 600; // 10 minutes in seconds

        __ERC165Storage_init();
        _registerInterface(_IVOLMEX_REPRICER_ID);
        __Ownable_init();
        _transferOwnership(_owner);
    }

    /**
     * @notice Used to set the duration between last price update
     * @param _newDuration Number of seconds of the timestamp duration
     */
    function updateAllowedDelay(uint256 _newDuration) external onlyOwner {
        allowedDelay = _newDuration;

        emit AllowedDelayUpdated(_newDuration);
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
        uint256 lastUpdateTimestamp;
        (estPrimaryPrice, estComplementPrice, lastUpdateTimestamp) = oracle.getIndexTwap(
            _volatilityIndex
        );
        require(
            (block.timestamp - lastUpdateTimestamp) <= allowedDelay,
            "VolmexRepricer: Stale oracle price"
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
}

// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.11;

import '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';

/**
 * @title Volmex Oracle contract
 * @author volmex.finance [security@volmexlabs.com]
 */
contract VolmexOracle is OwnableUpgradeable {
    event VolatilityTokenPriceUpdated(
        uint256 volatilityTokenPrice,
        uint256 volatilityIndex,
        bytes32 proofHash
    );

    event VolatilityTokenPriceAdded(
        uint256 indexed volatilityTokenIndex,
        string volatilityTokenSymbol,
        uint256 volatilityTokenPrice
    );

    // Store the price of volatility by indexes { 0 - ETHV, 1 = BTCV }
    mapping(uint256 => uint256) public volatilityTokenPriceByIndex;
    // Store the proof of hash of the current volatility token price
    mapping(uint256 => bytes32) public volatilityTokenPriceProofHash;
    // Store the symbol of volatility per index
    mapping(string => uint256) public volatilityIndexBySymbol;
    // Store the number of indexes
    uint256 public indexCount;

    /**
     * @notice Used to check the volatility token price
     */
    modifier _checkVolatilityPrice(uint256 _volatilityTokenPrice) {
        require(
            _volatilityTokenPrice <= 250000000,
            'VolmexOracle: _volatilityTokenPrice should be in range of 0 to 250'
        );
        _;
    }

    /**
     * @notice Initializes the contract setting the deployer as the initial owner.
     */
    function initialize() external initializer {
        __Ownable_init();
        volatilityTokenPriceByIndex[indexCount] = 125000000;
        volatilityTokenPriceProofHash[indexCount] = ''; // Add proof of hash bytes32 value
        volatilityIndexBySymbol['ETHV'] = indexCount;

        indexCount++;

        volatilityTokenPriceByIndex[indexCount] = 125000000;
        volatilityTokenPriceProofHash[indexCount] = ''; // Add proof of hash bytes32 value
        volatilityIndexBySymbol['BTCV'] = indexCount;
    }

    /**
     * @notice Updates the volatility token price by index
     *
     * @dev Check if volatility token price is greater than zero (0)
     * @dev Update the volatility token price corresponding to the volatility token symbol
     * @dev Store the volatility token price corresponding to the block number
     * @dev Update the proof of hash for the volatility token price
     *
     * @param _volatilityIndex Number value of the volatility index. { eg. 0 }
     * @param _volatilityTokenPrice Price of volatility token, between {0, 250000000}
     * @param _proofHash Bytes32 value of token price proof of hash
     *
     * NOTE: Make sure the volatility token price are with 6 decimals, eg. 125000000
     */
    function updateVolatilityTokenPrice(
        uint256 _volatilityIndex,
        uint256 _volatilityTokenPrice,
        bytes32 _proofHash
    )
        external
        onlyOwner
        _checkVolatilityPrice(_volatilityTokenPrice)
    {
        volatilityTokenPriceByIndex[_volatilityIndex] = _volatilityTokenPrice;
        volatilityTokenPriceProofHash[_volatilityIndex] = _proofHash;

        emit VolatilityTokenPriceUpdated(_volatilityTokenPrice, _volatilityIndex, _proofHash);
    }

    /**
     * @notice Add volatility token price by index
     *
     * @param _volatilityTokenPrice Price of the adding volatility token
     * @param _volatilityTokenSymbol Symbol of the adding volatility token
     * @param _proofHash Bytes32 value of token price proof of hash
     */
    function addVolatilityTokenPrice(
        uint256 _volatilityTokenPrice,
        string calldata _volatilityTokenSymbol,
        bytes32 _proofHash
    ) external onlyOwner _checkVolatilityPrice(_volatilityTokenPrice) {
        volatilityTokenPriceByIndex[++indexCount] = _volatilityTokenPrice;
        volatilityTokenPriceProofHash[indexCount] = _proofHash;
        volatilityIndexBySymbol[_volatilityTokenSymbol] = indexCount;


        emit VolatilityTokenPriceAdded(
            indexCount,
            _volatilityTokenSymbol,
            _volatilityTokenPrice
        );
    }

    /**
     * @notice Get the volatility token price by symbol
     *
     * @param _volatilityTokenSymbol Symbol of the volatility token
     */
    function getVolatilityPriceBySymbol(
        string calldata _volatilityTokenSymbol
    ) external view returns (uint256 volatilityTokenPrice) {
        volatilityTokenPrice = volatilityTokenPriceByIndex[volatilityIndexBySymbol[_volatilityTokenSymbol]];
    }
}

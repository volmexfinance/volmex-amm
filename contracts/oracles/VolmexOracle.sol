// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.7.6;

import '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';

/**
 * @title Volmex Oracle contract
 * @author volmex.finance [security@volmexlabs.com]
 */
contract VolmexOracle is OwnableUpgradeable {
    event VolatilityTokenPriceUpdated(uint256 volatilityTokenPrice);

    event VolatilityTokenPriceAdded(
        uint256 indexed volatilityTokenIndex,
        string volatilityTokenSymbol,
        uint256 volatilityTokenPrice
    );

    // Store the price of volatility of ETHV and BTCV
    mapping(string => uint256) public volatilityTokenPriceBySymbol;
    // Store the price of volatility by indexes { 0 - ETHV, 1 = BTCV }
    mapping(uint256 => uint256) public volatilityTokenPriceByIndex;
    // Store the proof of hash of the current volatility token price
    mapping(uint256 => bytes32) public volatilityTokenPriceProofHash;
    // Store the number of indexes
    uint256 public indexCount;

    uint256 private constant VOLATILITY_PRICE_PRECISION = 10000;

    /**
     * @notice Used to check the volatility token price
     */
    modifier _checkVolatilityPrice(uint256 _volatilityTokenPrice) {
        require(
            _volatilityTokenPrice <= 250,
            'VolmexOracle: _volatilityTokenPrice should be in range of 0 to 250'
        );
        _;
    }

    /**
     * @notice Initializes the contract setting the deployer as the initial owner.
     */
    function initialize() external initializer {
        __Ownable_init();
        volatilityTokenPriceByIndex[indexCount] = 1250000;
        volatilityTokenPriceBySymbol['ETHV'] = 1250000;
        volatilityTokenPriceProofHash[indexCount] = ''; // Add proof of hash bytes32 value

        indexCount++;

        volatilityTokenPriceByIndex[indexCount] = 1250000;
        volatilityTokenPriceBySymbol['BTCV'] = 1250000;
        volatilityTokenPriceProofHash[indexCount] = ''; // Add proof of hash bytes32 value
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
     * @param _volatilityTokenPrice Price of volatility token, between {0, 250}
     * @param _proofHash Bytes32 value of token price proof of hash
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
        volatilityTokenPriceByIndex[_volatilityIndex] = _volatilityTokenPrice * VOLATILITY_PRICE_PRECISION;
        volatilityTokenPriceProofHash[_volatilityIndex] = _proofHash;

        emit VolatilityTokenPriceUpdated(_volatilityTokenPrice);
    }

    /**
     * @notice Updates the volatility token price by symbol
     *
     * @dev Check if volatility token price is greater than zero (0)
     * @dev Update the volatility token price corresponding to the volatility token symbol
     * @dev Store the volatility token price corresponding to the block number
     *
     * @param _volatilityTokenSymbol sttring value of the volatility symbol. { eg. ETHV }
     * @param _volatilityTokenPrice Price of volatility token, between {0, 250}
     */
    function updateVolatilityTokenPriceBySymbol(
        string calldata _volatilityTokenSymbol,
        uint256 _volatilityTokenPrice
    ) external onlyOwner _checkVolatilityPrice(_volatilityTokenPrice) {
        volatilityTokenPriceBySymbol[_volatilityTokenSymbol] = _volatilityTokenPrice * VOLATILITY_PRICE_PRECISION;

        emit VolatilityTokenPriceUpdated(_volatilityTokenPrice);
    }

    /**
     * @notice Add volatility token price by index
     *
     * @param _volatilityTokenPrice Price of the adding volatility token
     * @param _volatilityTokenSymbol Symbol of the adding volatility token
     */
    function addVolatilityTokenPrice(
        uint256 _volatilityTokenPrice,
        string calldata _volatilityTokenSymbol,
        bytes32 _proofHash
    ) external onlyOwner _checkVolatilityPrice(_volatilityTokenPrice) {
        volatilityTokenPriceBySymbol[_volatilityTokenSymbol] = _volatilityTokenPrice * VOLATILITY_PRICE_PRECISION;
        volatilityTokenPriceByIndex[++indexCount] = _volatilityTokenPrice * VOLATILITY_PRICE_PRECISION;
        volatilityTokenPriceProofHash[indexCount] = _proofHash;

        emit VolatilityTokenPriceAdded(
            indexCount,
            _volatilityTokenSymbol,
            _volatilityTokenPrice
        );
    }
}

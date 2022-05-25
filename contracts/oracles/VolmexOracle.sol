// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.11;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165StorageUpgradeable.sol";

import "../interfaces/IVolmexProtocol.sol";
import "../interfaces/IVolmexOracle.sol";
import "./VolmexTWAP.sol";

/**
 * @title Volmex Oracle contract
 * @author volmex.finance [security@volmexlabs.com]
 */
contract VolmexOracle is OwnableUpgradeable, ERC165StorageUpgradeable, VolmexTWAP, IVolmexOracle {
    // price precision constant upto 6 decimal places
    uint256 private constant _VOLATILITY_PRICE_PRECISION = 1000000;
    // Interface ID of VolmexOracle contract, hashId = 0xf9fffc9f
    bytes4 private constant _IVOLMEX_ORACLE_ID = type(IVolmexOracle).interfaceId;

    // Store the price of volatility by indexes { 0 - ETHV, 1 = BTCV }
    mapping(uint256 => uint256) private _volatilityTokenPriceByIndex;

    // Store the volatilitycapratio by index
    mapping(uint256 => uint256) public volatilityCapRatioByIndex;
    // Store the proof of hash of the current volatility token price
    mapping(uint256 => bytes32) public volatilityTokenPriceProofHash;
    // Store the index of volatility by symbol
    mapping(string => uint256) public volatilityIndexBySymbol;
    // Store the leverage on volatility by index
    mapping(uint256 => uint256) public volatilityLeverageByIndex;
    // Store the base volatility index by leverage volatility index
    mapping(uint256 => uint256) public baseVolatilityIndex;
    // Store the number of indexes
    uint256 public indexCount;
    // Store the timestamp of volatility price update by index
    mapping(uint256 => uint256) public volatilityTokensPriceTimestamp;

    /**
     * @notice Initializes the contract setting the deployer as the initial owner.
     */
    function initialize(address _owner) external initializer {
        _volatilityTokenPriceByIndex[indexCount] = 125000000;
        volatilityTokenPriceProofHash[indexCount] = ""; // Add proof of hash bytes32 value
        volatilityIndexBySymbol["ETHV"] = indexCount;
        volatilityCapRatioByIndex[indexCount] = 250000000;
        _addIndexDataPoint(indexCount, 125000000);

        uint256 currentTimestamp = block.timestamp;
        volatilityTokensPriceTimestamp[indexCount] = currentTimestamp;

        indexCount++;

        _volatilityTokenPriceByIndex[indexCount] = 125000000;
        volatilityTokenPriceProofHash[indexCount] = ""; // Add proof of hash bytes32 value
        volatilityIndexBySymbol["BTCV"] = indexCount;
        volatilityCapRatioByIndex[indexCount] = 250000000;
        _addIndexDataPoint(indexCount, 125000000);
        volatilityTokensPriceTimestamp[indexCount] = currentTimestamp;

        __Ownable_init();
        __ERC165Storage_init();
        _registerInterface(_IVOLMEX_ORACLE_ID);
        _transferOwnership(_owner);
    }

    /**
     * @notice Adds a new datapoint to the datapoints storage array
     *
     * @param _index Datapoints volatility index id {0}
     * @param _value Datapoint value to add {250000000}
     */
    function addIndexDataPoint(uint256 _index, uint256 _value) external onlyOwner {
        _addIndexDataPoint(_index, _value);
    }

    /**
     * @notice Update the volatility token index by symbol
     * @param _index Number value of the index. { eg. 0 }
     * @param _tokenSymbol Symbol of the adding volatility token
     */
    function updateIndexBySymbol(string calldata _tokenSymbol, uint256 _index) external onlyOwner {
        volatilityIndexBySymbol[_tokenSymbol] = _index;

        emit SymbolIndexUpdated(_index);
    }

    /**
     * @notice Update the baseVolatilityIndex of leverage token
     * @param _leverageVolatilityIndex Index of the leverage volatility token
     * @param _newBaseVolatilityIndex Index of the base volatility token
     */
    function updateBaseVolatilityIndex(
        uint256 _leverageVolatilityIndex,
        uint256 _newBaseVolatilityIndex
    ) external onlyOwner {
        baseVolatilityIndex[_leverageVolatilityIndex] = _newBaseVolatilityIndex;

        emit BaseVolatilityIndexUpdated(_newBaseVolatilityIndex);
    }

    /**
     * @notice Add volatility token price by index
     * @param _volatilityTokenPrice Price of the adding volatility token
     * @param _protocol Address of the VolmexProtocol of which the price is added
     * @param _volatilityTokenSymbol Symbol of the adding volatility token
     * @param _leverage Value of leverage on token {2X: 2, 5X: 5}
     * @param _baseVolatilityIndex Index of the base volatility {0: ETHV, 1: BTCV}
     * @param _proofHash Bytes32 value of token price proof of hash
     */
    function addVolatilityIndex(
        uint256 _volatilityTokenPrice,
        IVolmexProtocol _protocol,
        string calldata _volatilityTokenSymbol,
        uint256 _leverage,
        uint256 _baseVolatilityIndex,
        bytes32 _proofHash
    ) external onlyOwner {
        require(address(_protocol) != address(0), "VolmexOracle: protocol address can't be zero");
        uint256 _volatilityCapRatio = _protocol.volatilityCapRatio() * _VOLATILITY_PRICE_PRECISION;
        require(
            _volatilityCapRatio >= 1000000,
            "VolmexOracle: volatility cap ratio should be greater than 1000000"
        );
        uint256 _index = ++indexCount;
        volatilityCapRatioByIndex[_index] = _volatilityCapRatio;
        volatilityIndexBySymbol[_volatilityTokenSymbol] = _index;
        volatilityTokensPriceTimestamp[_index] = block.timestamp;

        if (_leverage >= 2) {
            // This will also check the base volatilities are present
            require(
                volatilityCapRatioByIndex[_baseVolatilityIndex] / _leverage == _volatilityCapRatio,
                "VolmexOracle: Invalid _baseVolatilityIndex provided"
            );
            volatilityLeverageByIndex[_index] = _leverage;
            baseVolatilityIndex[_index] = _baseVolatilityIndex;
            _addIndexDataPoint(
                _index,
                _volatilityTokenPriceByIndex[_baseVolatilityIndex] / _leverage
            );

            emit LeveragedVolatilityIndexAdded(
                _index,
                _volatilityCapRatio,
                _volatilityTokenSymbol,
                _leverage,
                _baseVolatilityIndex
            );
        } else {
            require(
                _volatilityTokenPrice <= _volatilityCapRatio,
                "VolmexOracle: _volatilityTokenPrice should be smaller than VolatilityCapRatio"
            );
            _volatilityTokenPriceByIndex[_index] = _volatilityTokenPrice;
            volatilityTokenPriceProofHash[_index] = _proofHash;
            _addIndexDataPoint(_index, _volatilityTokenPrice);

            emit VolatilityIndexAdded(
                _index,
                _volatilityCapRatio,
                _volatilityTokenSymbol,
                _volatilityTokenPrice
            );
        }
    }

    /**
     * @notice Updates the volatility token price by index
     *
     * @dev Check if volatility token price is greater than zero (0)
     * @dev Update the volatility token price corresponding to the volatility token symbol
     * @dev Store the volatility token price corresponding to the block number
     * @dev Update the proof of hash for the volatility token price
     *
     * @param _volatilityIndexes Number array of values of the volatility index. { eg. 0 }
     * @param _volatilityTokenPrices array of prices of volatility token, between {0, 250000000}
     * @param _proofHashes arrau of Bytes32 values of token prices proof of hash
     *
     * NOTE: Make sure the volatility token price are with 6 decimals, eg. 125000000
     */
    function updateBatchVolatilityTokenPrice(
        uint256[] memory _volatilityIndexes,
        uint256[] memory _volatilityTokenPrices,
        bytes32[] memory _proofHashes
    ) external onlyOwner {
        require(
            _volatilityIndexes.length == _volatilityTokenPrices.length &&
                _volatilityIndexes.length == _proofHashes.length,
            "VolmexOracle: length of input arrays are not equal"
        );
        uint256 currentTimestamp = block.timestamp;
        for (uint256 i = 0; i < _volatilityIndexes.length; i++) {
            require(
                _volatilityTokenPrices[i] <= volatilityCapRatioByIndex[_volatilityIndexes[i]],
                "VolmexOracle: _volatilityTokenPrice should be smaller than VolatilityCapRatio"
            );

            _addIndexDataPoint(_volatilityIndexes[i], _volatilityTokenPrices[i]);

            _volatilityTokenPriceByIndex[_volatilityIndexes[i]] = _getIndexTwap(
                _volatilityIndexes[i]
            );
            volatilityTokenPriceProofHash[_volatilityIndexes[i]] = _proofHashes[i];
            volatilityTokensPriceTimestamp[_volatilityIndexes[i]] = currentTimestamp;
        }

        emit BatchVolatilityTokenPriceUpdated(
            _volatilityIndexes,
            _volatilityTokenPrices,
            _proofHashes
        );
    }

    /**
     * @notice Get the volatility token price by symbol
     * @param _volatilityTokenSymbol Symbol of the volatility token
     */
    function getVolatilityPriceBySymbol(string calldata _volatilityTokenSymbol)
        external
        view
        returns (
            uint256 volatilityTokenPrice,
            uint256 iVolatilityTokenPrice,
            uint256 priceTimestamp
        )
    {
        uint256 volatilityIndex = volatilityIndexBySymbol[_volatilityTokenSymbol];
        if (volatilityLeverageByIndex[volatilityIndex] > 0) {
            uint256 baseIndex = baseVolatilityIndex[volatilityIndex];
            volatilityTokenPrice = _volatilityTokenPriceByIndex[baseIndex] / volatilityLeverageByIndex[volatilityIndex];
            priceTimestamp = volatilityTokensPriceTimestamp[baseIndex];
        } else {
            volatilityTokenPrice = _volatilityTokenPriceByIndex[volatilityIndex];
            priceTimestamp = volatilityTokensPriceTimestamp[volatilityIndex];
        }
        iVolatilityTokenPrice = volatilityCapRatioByIndex[volatilityIndex] - volatilityTokenPrice;
    }

    /**
     * @notice Get the volatility token price by index
     * @param _index index of the volatility token
     */
    function getVolatilityTokenPriceByIndex(uint256 _index)
        external
        view
        returns (
            uint256 volatilityTokenPrice,
            uint256 iVolatilityTokenPrice,
            uint256 priceTimestamp
        )
    {
        if (volatilityLeverageByIndex[_index] > 0) {
            uint256 baseIndex = baseVolatilityIndex[_index];
            volatilityTokenPrice = _volatilityTokenPriceByIndex[baseIndex] / volatilityLeverageByIndex[_index];
            priceTimestamp = volatilityTokensPriceTimestamp[baseIndex];
        } else {
            volatilityTokenPrice = _volatilityTokenPriceByIndex[_index];
            priceTimestamp = volatilityTokensPriceTimestamp[_index];
        }
        iVolatilityTokenPrice = volatilityCapRatioByIndex[_index] - volatilityTokenPrice;
    }

    /**
     * @notice Get the TWAP value from current available datapoints
     * @param _index Datapoints volatility index id {0}
     */
    function getIndexTwap(uint256 _index)
        external
        view
        returns (
            uint256 volatilityTokenTwap,
            uint256 iVolatilityTokenTwap,
            uint256 twapTimestamp
        )
    {
        if (volatilityLeverageByIndex[_index] > 0) {
            uint256 baseIndex = baseVolatilityIndex[_index];
            volatilityTokenTwap = (_getIndexTwap(baseIndex)) / volatilityLeverageByIndex[_index];
            twapTimestamp = volatilityTokensPriceTimestamp[baseIndex];
        } else {
            volatilityTokenTwap = _getIndexTwap(_index);
            twapTimestamp = volatilityTokensPriceTimestamp[_index];
        }
        iVolatilityTokenTwap = volatilityCapRatioByIndex[_index] - volatilityTokenTwap;
    }

    /**
     * @notice Get all datapoints available for a specific volatility index
     * @param _index Datapoints volatility index id {0}
     */
    function getIndexDataPoints(uint256 _index) external view returns (uint256[] memory dp) {
        dp = _getIndexDataPoints(_index);
    }

    /**
     * @notice Emulate the Chainlink Oracle interface for retrieving Volmex TWAP volatility index
     * @param _index Datapoints volatility index id {0}
     * @return answer is the answer for the given round
     */
    function latestRoundData(uint256 _index)
        external
        view
        virtual
        override
        returns (uint256 answer)
    {
        answer = _getIndexTwap(_index) * 100;
    }
}

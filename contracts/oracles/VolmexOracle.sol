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
    // maximum allowed number of index volatility datapoints for calculating twap
    uint256 private constant _MAX_ALLOWED_TWAP_DATAPOINTS = 180;
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
    mapping(uint256 => uint256) public volatilityLastUpdateTimestamp;

    /**
     * @notice Initializes the contract setting the deployer as the initial owner.
     */
    function initialize(address _owner) external initializer {
        _updateTwapMaxDatapoints(_MAX_ALLOWED_TWAP_DATAPOINTS);

        _updateVolatilityMeta(indexCount, 125000000, "");
        volatilityIndexBySymbol["ETHV"] = indexCount;
        volatilityCapRatioByIndex[indexCount] = 250000000;

        indexCount++;

        _updateVolatilityMeta(indexCount, 125000000, "");
        volatilityIndexBySymbol["BTCV"] = indexCount;
        volatilityCapRatioByIndex[indexCount] = 250000000;

        __Ownable_init();
        __ERC165Storage_init();
        _registerInterface(_IVOLMEX_ORACLE_ID);
        _transferOwnership(_owner);
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

        if (_leverage > 1) {
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
            _updateVolatilityMeta(_index, _volatilityTokenPrice, _proofHash);

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
        for (uint256 i = 0; i < _volatilityIndexes.length; i++) {
            require(
                _volatilityTokenPrices[i] <= volatilityCapRatioByIndex[_volatilityIndexes[i]],
                "VolmexOracle: _volatilityTokenPrice should be smaller than VolatilityCapRatio"
            );

            _updateVolatilityMeta(
                _volatilityIndexes[i],
                _volatilityTokenPrices[i],
                _proofHashes[i]
            );
        }

        emit BatchVolatilityTokenPriceUpdated(
            _volatilityIndexes,
            _volatilityTokenPrices,
            _proofHashes
        );
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
     * @notice Get the volatility token price by symbol
     * @param _volatilityTokenSymbol Symbol of the volatility token
     */
    function getVolatilityPriceBySymbol(string calldata _volatilityTokenSymbol)
        external
        view
        returns (
            uint256 volatilityTokenPrice,
            uint256 iVolatilityTokenPrice,
            uint256 lastUpdateTimestamp
        )
    {
        uint256 volatilityIndex = volatilityIndexBySymbol[_volatilityTokenSymbol];
        (
            volatilityTokenPrice,
            iVolatilityTokenPrice,
            lastUpdateTimestamp
        ) = _getVolatilityTokenPrice(volatilityIndex);
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
            uint256 lastUpdateTimestamp
        )
    {
        (
            volatilityTokenPrice,
            iVolatilityTokenPrice,
            lastUpdateTimestamp
        ) = _getVolatilityTokenPrice(_index);
    }

    /**
     * @notice Get the TWAP value from current available datapoints
     * @param _index Datapoints volatility index id {0}
     *
     * @dev This method is a replica of `getVolatilityTokenPriceByIndex(_index)`
     */
    function getIndexTwap(uint256 _index)
        external
        view
        returns (
            uint256 volatilityTokenTwap,
            uint256 iVolatilityTokenTwap,
            uint256 lastUpdateTimestamp
        )
    {
        (
            volatilityTokenTwap,
            iVolatilityTokenTwap,
            lastUpdateTimestamp
        ) = _getVolatilityTokenPrice(_index);
    }

    /**
     * @notice Get all datapoints available for a specific volatility index
     * @param _index Datapoints volatility index id {0}
     */
    function getIndexDataPoints(uint256 _index) external view returns (uint256[] memory dp) {
        dp = _getIndexDataPoints(_index);
    }

    /**
     * @notice Update maximum amount of volatility index datapoints for calculating the TWAP
     *
     * @param _value Max datapoints value {180}
     */
    function updateTwapMaxDatapoints(uint256 _value) external onlyOwner {
        _updateTwapMaxDatapoints(_value);
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
        returns (uint256 answer, uint256 lastUpdateTimestamp)
    {
        answer = _getIndexTwap(_index) * 100;
        lastUpdateTimestamp = volatilityLeverageByIndex[_index] > 0
            ? volatilityLastUpdateTimestamp[baseVolatilityIndex[_index]]
            : volatilityLastUpdateTimestamp[_index];
    }

    function _updateVolatilityMeta(
        uint256 _index,
        uint256 _volatilityTokenPrice,
        bytes32 _proofHash
    ) private {
        _addIndexDataPoint(_index, _volatilityTokenPrice);
        _volatilityTokenPriceByIndex[_index] = _getIndexTwap(_index);
        volatilityLastUpdateTimestamp[_index] = block.timestamp;
        volatilityTokenPriceProofHash[_index] = _proofHash;
    }

    function _getVolatilityTokenPrice(uint256 _index)
        private
        view
        returns (
            uint256 volatilityTokenTwap,
            uint256 iVolatilityTokenTwap,
            uint256 lastUpdateTimestamp
        )
    {
        if (volatilityLeverageByIndex[_index] > 0) {
            uint256 baseIndex = baseVolatilityIndex[_index];
            volatilityTokenTwap = (_getIndexTwap(baseIndex)) / volatilityLeverageByIndex[_index];
            lastUpdateTimestamp = volatilityLastUpdateTimestamp[baseIndex];
        } else {
            volatilityTokenTwap = _getIndexTwap(_index);
            lastUpdateTimestamp = volatilityLastUpdateTimestamp[_index];
        }
        iVolatilityTokenTwap = volatilityCapRatioByIndex[_index] - volatilityTokenTwap;
    }
}

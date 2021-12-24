// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.11;

import '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';
import '../interfaces/IVolmexProtocol.sol';

/**
 * @title Volmex Oracle contract
 * @author volmex.finance [security@volmexlabs.com]
 */
contract VolmexOracle is OwnableUpgradeable {
    // Store the price of volatility by indexes { 0 - ETHV, 1 = BTCV }
    mapping(uint256 => uint256) private _volatilityTokenPriceByIndex;
    // Store the volatilitycapratio by index
    mapping(uint256 => uint256) public volatilityCapRatioByIndex;
    // Store the proof of hash of the current volatility token price
    mapping(uint256 => bytes32) public volatilityTokenPriceProofHash;
    // Store the index of volatility by symbol
    mapping(string => uint256) public volatilityIndexBySymbol;
    // Store the number of indexes
    uint256 public indexCount;
    // price precision constant upto 6 decimal places
    uint256 private constant VOLATILITY_PRICE_PRECISION = 1000000;

    event BatchVolatilityTokenPriceUpdated(
        uint256[] _volatilityIndexes,
        uint256[] _volatilityTokenPrices,
        bytes32[] _proofHashes
    );

    event VolatilityIndexAdded(
        uint256 indexed volatilityTokenIndex,
        uint256 volatilityCapRatio,
        string volatilityTokenSymbol,
        uint256 volatilityTokenPrice
    );

    event ProtocolUpdated(address _protocol);

    /**
     * @notice Initializes the contract setting the deployer as the initial owner.
     */
    function initialize() external initializer {
        __Ownable_init();
        _volatilityTokenPriceByIndex[indexCount] = 125000000;
        volatilityTokenPriceProofHash[indexCount] = ''; // Add proof of hash bytes32 value
        volatilityIndexBySymbol['ETHV'] = indexCount;
        volatilityCapRatioByIndex[indexCount] = 250000000;

        indexCount++;

        _volatilityTokenPriceByIndex[indexCount] = 125000000;
        volatilityTokenPriceProofHash[indexCount] = ''; // Add proof of hash bytes32 value
        volatilityIndexBySymbol['BTCV'] = indexCount;
        volatilityCapRatioByIndex[indexCount] = 250000000;
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
            'VolmexOracle: length of input arrays are not equal'
        );
        for (uint256 i = 0; i < _volatilityIndexes.length; i++) {
            require(
                _volatilityTokenPrices[i] <= volatilityCapRatioByIndex[_volatilityIndexes[i]],
                'VolmexOracle: _volatilityTokenPrice should be smaller than VolatilityCapRatio'
            );
            _volatilityTokenPriceByIndex[_volatilityIndexes[i]] = _volatilityTokenPrices[i];
            volatilityTokenPriceProofHash[_volatilityIndexes[i]] = _proofHashes[i];
        }

        emit BatchVolatilityTokenPriceUpdated(
            _volatilityIndexes,
            _volatilityTokenPrices,
            _proofHashes
        );
    }

    /**
     * @notice Add volatility token price by index
     *
     * @param _volatilityTokenPrice Price of the adding volatility token
     * @param _volatilityTokenSymbol Symbol of the adding volatility token
     * @param _proofHash Bytes32 value of token price proof of hash
     */
    function addVolatilityIndex(
        uint256 _volatilityTokenPrice,
        IVolmexProtocol _protocol,
        string calldata _volatilityTokenSymbol,
        bytes32 _proofHash
    ) external onlyOwner {
        require(address(_protocol) != address(0), "volmexOracle: protocol address can't be zero");
        uint256 _volatilityCapRatio = _protocol.volatilityCapRatio() * VOLATILITY_PRICE_PRECISION;
        require(
            _volatilityCapRatio >= 1000000,
            'VolmexOracle: volatility cap ratio should be greater than 1000000'
        );
        require(
            _volatilityTokenPrice <= _volatilityCapRatio,
            'VolmexOracle: _volatilityTokenPrice should be smaller than VolatilityCapRatio'
        );
        uint256 _index = ++indexCount;
        volatilityCapRatioByIndex[_index] = _volatilityCapRatio;

        _volatilityTokenPriceByIndex[_index] = _volatilityTokenPrice;
        volatilityTokenPriceProofHash[_index] = _proofHash;
        volatilityIndexBySymbol[_volatilityTokenSymbol] = _index;

        emit VolatilityIndexAdded(
            _index,
            _volatilityCapRatio,
            _volatilityTokenSymbol,
            _volatilityTokenPrice
        );
    }

    /**
     * @notice Get the volatility token price by symbol
     *
     * @param _volatilityTokenSymbol Symbol of the volatility token
     */
    function getVolatilityPriceBySymbol(string calldata _volatilityTokenSymbol)
        external
        view
        returns (uint256 volatilityTokenPrice, uint256 iVolatilityTokenPrice)
    {
        volatilityTokenPrice = _volatilityTokenPriceByIndex[
            volatilityIndexBySymbol[_volatilityTokenSymbol]
        ];
        iVolatilityTokenPrice =
            volatilityCapRatioByIndex[volatilityIndexBySymbol[_volatilityTokenSymbol]] -
            volatilityTokenPrice;
    }

    /**
     * @notice Get the volatility token price by index
     *
     * @param _index index of the volatility token
     */
    function getVolatilityTokenPriceByIndex(uint256 _index)
        external
        view
        returns (uint256 volatilityTokenPrice, uint256 iVolatilityTokenPrice)
    {
        volatilityTokenPrice = _volatilityTokenPriceByIndex[_index];
        iVolatilityTokenPrice = volatilityCapRatioByIndex[_index] - volatilityTokenPrice;
    }
}

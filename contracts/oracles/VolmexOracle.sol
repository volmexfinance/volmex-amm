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

    event VolatilityCapRatioUpdated(uint256 indexed _index, uint256 _volatilityCapRatio);

    // Store the price of volatility by indexes { 0 - ETHV, 1 = BTCV }
    mapping(uint256 => uint256) private _volatilityTokenPriceByIndex;
    // Store the volatilitycapratio by index
    mapping(uint256 => uint256) public volatilityCapRatioByIndex;
    // Store the proof of hash of the current volatility token price
    mapping(uint256 => bytes32) public volatilityTokenPriceProofHash;
    // Store the symbol of volatility per index
    mapping(string => uint256) public volatilityIndexBySymbol;
    // Store the number of indexes
    uint256 public indexCount;

    /**
     * @notice Used to check the volatility token price
     */
    modifier _checkVolatilityPrice(uint256 _index, uint256 _volatilityTokenPrice) {
        require(
            _volatilityTokenPrice <= volatilityCapRatioByIndex[_index],
            'VolmexOracle: _volatilityTokenPrice should be greater than 1000000'
        );
        _;
    }

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
     * @param _index index of volatilitycap ratio
     * @param _proofHash Bytes32 value of token price proof of hash
     *
     * NOTE: Make sure the volatility token price are with 6 decimals, eg. 125000000
     */
    function updateVolatilityTokenPrice(
        uint256 _volatilityIndex,
        uint256 _volatilityTokenPrice,
        uint256 _index,
        bytes32 _proofHash
    ) external onlyOwner _checkVolatilityPrice(_index, _volatilityTokenPrice) {
        _volatilityTokenPriceByIndex[_volatilityIndex] = _volatilityTokenPrice;
        volatilityTokenPriceProofHash[_volatilityIndex] = _proofHash;

        emit VolatilityTokenPriceUpdated(_volatilityTokenPrice, _volatilityIndex, _proofHash);
    }

    /**
     * @notice Updates the volatility cap ratio by index
     *
     * @dev Check if volatility token price is greater than zero (0)
     * @dev Update the volatility token price corresponding to the volatility token symbol
     * @dev Store the volatility token price corresponding to the block number
     * @dev Update the proof of hash for the volatility token price
     *
     * @param _index Number value of the volatility index. { eg. 0 }
     * @param _volatilityCapRatio volatility cap ratio, between {0, 250000000}
     *
     * NOTE: Make sure the volatility cap ratio are with 6 decimals, eg. 125000000
     */
    function updateVolatilityCapRatio(uint256 _index, uint256 _volatilityCapRatio) external onlyOwner {
        require(
            _volatilityCapRatio >= 1000000,
            'VolmexOracle: volatility cap ratio should be greater than 1000000'
        );
        volatilityCapRatioByIndex[_index] = _volatilityCapRatio;

        emit VolatilityCapRatioUpdated(_index, _volatilityCapRatio);
    }

    /**
     * @notice Add volatility token price by index
     *
     * @param _volatilityTokenPrice Price of the adding volatility token
     * @param _index index of volatilitycap ratio
     * @param _volatilityTokenSymbol Symbol of the adding volatility token
     * @param _proofHash Bytes32 value of token price proof of hash
     */
    function addVolatilityTokenPrice(
        uint256 _volatilityTokenPrice,
        uint256 _index,
        string calldata _volatilityTokenSymbol,
        bytes32 _proofHash
    ) external onlyOwner _checkVolatilityPrice(_index, _volatilityTokenPrice) {
        _volatilityTokenPriceByIndex[++indexCount] = _volatilityTokenPrice;
        volatilityTokenPriceProofHash[indexCount] = _proofHash;
        volatilityIndexBySymbol[_volatilityTokenSymbol] = indexCount;

        emit VolatilityTokenPriceAdded(indexCount, _volatilityTokenSymbol, _volatilityTokenPrice);
    }

    /**
     * @notice Get the volatility token price by symbol
     *
     * @param _volatilityTokenSymbol Symbol of the volatility token
     */
    function getVolatilityPriceBySymbol(string calldata _volatilityTokenSymbol)
        external
        view
        returns (uint256 volatilityTokenPrice)
    {
        volatilityTokenPrice = _volatilityTokenPriceByIndex[
            volatilityIndexBySymbol[_volatilityTokenSymbol]
        ];
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

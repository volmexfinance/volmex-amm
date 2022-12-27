// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.17;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/ClonesUpgradeable.sol";

import "../interfaces/IERC20Modified.sol";
import "contracts/interfaces/ILayerZeroVolmexPositionToken.sol";
import "./VolmexProtocol.sol";


/**
 * @title Factory Contract
 * @author volmex.finance [security@volmexlabs.com]
 */
contract VolmexIndexFactoryV2 is OwnableUpgradeable {
    event IndexRegistered(
        uint256 indexed indexCount,
        VolmexProtocol indexed index
    );

    event VolatilityTokenCreated(
        IERC20Modified indexed volatilityToken,
        IERC20Modified indexed inverseVolatilityToken,
        string tokenName,
        string tokenSymbol,
        string inverseTokenName,
        string inverseTokenSymbol
    );

    // Volatility token implementation contract for factory
    address public positionTokenImplementation;

    // To store the address of volatility.
    mapping(uint256 => address) public getIndex;

    // To store the name of volatility
    mapping(uint256 => string) public getIndexSymbol;

    // Used to store the address and name of volatility at a particular _index (incremental state of 1)
    uint256 public indexCount;

    // These are position token roles
    // Calculated as keccak256("VOLMEX_PROTOCOL_ROLE").
    bytes32 private constant VOLMEX_PROTOCOL_ROLE =
        0x33ba6006595f7ad5c59211bde33456cab351f47602fc04f644c8690bc73c4e16;

    // Referenced from Openzepplin AccessControl.sol
    bytes32 private constant DEFAULT_ADMIN_ROLE = 0x00;

    /**
     * @notice Get the address of implementation contracts instance.
     */
    function initialize(address _implementation) external initializer {
        __Ownable_init();

        positionTokenImplementation = _implementation;
    }

    /**
     * @notice Get the counterfactual address of position token implementation
     */
    function determineVolatilityTokenAddress(
        uint256 _indexCount,
        string memory _name,
        string memory _symbol
    ) external view returns (address) {
        bytes32 salt = keccak256(abi.encodePacked(_indexCount, _name, _symbol));
        return
            ClonesUpgradeable.predictDeterministicAddress(
                positionTokenImplementation,
                salt,
                address(this)
            );
    }

    /**
     * @notice Clones new volatility tokens - { returns volatility tokens address typecasted to IERC20Modified }
     *
     * @dev Increment the indexCount by 1
     * @dev Check if state is at NotInitialized
     * @dev Clones the volatility and inverse volatility tokens
     * @dev Stores the volatility name, referenced by indexCount
     * @dev Emits event of volatility token name & symbol, indexCount(position), position tokens address
     *
     * @param _tokenName is the name for volatility
     * @param _tokenSymbol is the symbol for volatility
     * @param _inverseTokenName is the name for inverse volatility
     * @param _inverseTokenSymbol is the symbol for inverse volatility
     */
    function createVolatilityTokens(
        string memory _tokenName,
        string memory _tokenSymbol,
        string memory _inverseTokenName,
        string memory _inverseTokenSymbol
    )
        external
        onlyOwner
        returns (
            IERC20Modified volatilityToken,
            IERC20Modified inverseVolatilityToken
        )
    {
        volatilityToken = IERC20Modified(
            _clonePositonToken(_tokenName, _tokenSymbol)
        );
        inverseVolatilityToken = IERC20Modified(
            _clonePositonToken(_inverseTokenName, _inverseTokenSymbol)
        );

        emit VolatilityTokenCreated(
            volatilityToken,
            inverseVolatilityToken,
            _tokenName,
            _tokenSymbol,
            _inverseTokenName,
            _inverseTokenSymbol
        );
    }

    /**
     * @notice Clones new volatility tokens for layer zero - { returns volatility tokens address typecasted to IERC20Modified }
     *
     * @dev Increment the indexCount by 1
     * @dev Check if state is at NotInitialized
     * @dev Clones the volatility and inverse volatility tokens
     * @dev Stores the volatility name, referenced by indexCount
     * @dev Emits event of volatility token name & symbol, indexCount(position), position tokens address
     *
     * @param _tokenName is the name for volatility
     * @param _tokenSymbol is the symbol for volatility
     * @param _inverseTokenName is the name for inverse volatility
     * @param _inverseTokenSymbol is the symbol for inverse volatility
     */
    function createLayerZeroVolatilityTokens(
        string memory _tokenName,
        string memory _tokenSymbol,
        string memory _inverseTokenName,
        string memory _inverseTokenSymbol,
        address _lzEndPoint
    )
        external
        onlyOwner
        returns (
            IERC20Modified volatilityToken,
            IERC20Modified inverseVolatilityToken
        )
    {
        volatilityToken = IERC20Modified(
            _cloneLayerZeroPositonToken(_tokenName, _tokenSymbol, _lzEndPoint)
        );
        inverseVolatilityToken = IERC20Modified(
            _cloneLayerZeroPositonToken(_inverseTokenName, _inverseTokenSymbol, _lzEndPoint)
        );

        emit VolatilityTokenCreated(
            volatilityToken,
            inverseVolatilityToken,
            _tokenName,
            _tokenSymbol,
            _inverseTokenName,
            _inverseTokenSymbol
        );
    }

    /**
     * @notice Registers the Volmex Protocol
     *
     * @dev Check if state is at VolatilitysCreated
     * @dev Stores index address, referenced by indexCount
     * @dev Grants the VOLMEX_PROTOCOL_ROLE and DEFAULT_ADMIN_ROLE to protocol
     * @dev Update index state to Completed
     * @dev Emit event of index registered with indexCount and index address
     *
     * @param _volmexProtocolContract Address of VolmexProtocol typecasted to VolmexProtocol
     * @param _collateralSymbol Symbol of collateral used
     */
    function registerIndex(
        VolmexProtocol _volmexProtocolContract,
        string memory _collateralSymbol
    ) external onlyOwner {
        indexCount++;

        getIndex[indexCount] = address(_volmexProtocolContract);

        IERC20Modified volatilityToken =
            _volmexProtocolContract.volatilityToken();
        IERC20Modified inverseVolatilityToken =
            _volmexProtocolContract.inverseVolatilityToken();

        getIndexSymbol[indexCount] = string(
            abi.encodePacked(volatilityToken.symbol(), _collateralSymbol)
        );

        volatilityToken.grantRole(
            VOLMEX_PROTOCOL_ROLE,
            address(_volmexProtocolContract)
        );

        inverseVolatilityToken.grantRole(
            VOLMEX_PROTOCOL_ROLE,
            address(_volmexProtocolContract)
        );

        volatilityToken.grantRole(DEFAULT_ADMIN_ROLE, msg.sender);

        inverseVolatilityToken.grantRole(DEFAULT_ADMIN_ROLE, msg.sender);

        emit IndexRegistered(indexCount, _volmexProtocolContract);
    }

    /**
     * @notice Clones the position token - { returns position token address }
     *
     * @dev Generates a salt using indexCount, token name and token symbol
     * @dev Clone the position token implementation with a salt make it deterministic
     * @dev Initializes the position token
     *
     * @param _name is the name of volatility token
     * @param _symbol is the symbol of volatility token
     */
    function _clonePositonToken(string memory _name, string memory _symbol)
        private
        returns (address newVolatilityToken)
    {
        bytes32 salt = keccak256(abi.encodePacked(indexCount, _name, _symbol));
        newVolatilityToken = ClonesUpgradeable.cloneDeterministic(positionTokenImplementation, salt);
        VolmexPositionToken(newVolatilityToken).initialize(_name, _symbol);
        return newVolatilityToken;
    }

    /**
     * @notice Clones the position token - { returns position token address }
     *
     * @dev Generates a salt using indexCount, token name and token symbol
     * @dev Clone the position token implementation with a salt make it deterministic
     * @dev Initializes the position token
     *
     * @param _name is the name of volatility token
     * @param _symbol is the symbol of volatility token
     */
    function _cloneLayerZeroPositonToken(string memory _name, string memory _symbol, address _lzEndPoint)
        private
        returns (address newVolatilityToken)
    {
        bytes32 salt = keccak256(abi.encodePacked(indexCount, _name, _symbol));
        newVolatilityToken = ClonesUpgradeable.cloneDeterministic(positionTokenImplementation, salt);
        ILayerZeroVolmexPositionToken(newVolatilityToken).__LayerZero_init(_name, _symbol, _lzEndPoint);
        return newVolatilityToken;
    }
}

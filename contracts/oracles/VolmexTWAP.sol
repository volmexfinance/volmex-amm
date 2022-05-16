// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.11;

/**
 * @title Volmex Oracle TWAP library
 * @author volmex.finance [security@volmexlabs.com]
 */
contract VolmexTWAP {
    // Max datapoints allowed to store in
    uint8 private constant _MAX_DATAPOINTS = 180;

    // Datapoint object structure
    struct DataPoint { 
      uint256 value;
      uint256 timestamp;
    }

    // Emit new event when new datapoint is added
    event IndexDataPointAdded(
      uint256 indexed_index,
      uint256 _value
    );

    // Store index datapoints into multidimensional arrays
    mapping(uint256 => uint256[]) private _datapoints;

    // In order to maintain low gas fees and storage efficiency we use cursors to store datapoints
    mapping(uint256 => uint256) private _datapointsCursor;

    /**
     * @notice Adds a new datapoint to the datapoints storage array
     *
     * @param _index Datapoints volatility index id {0}
     * @param _value Datapoint value to add {250000000}
     */
    function _addIndexDataPoint(uint256 _index, uint256 _value) internal {
      if ( _datapoints[_index].length < _MAX_DATAPOINTS) {
        // initially populate available datapoint storage slots with index data
        _datapoints[_index].push(_value);
      } else {
        if (
          // check if cursor has reached the maximum allowed storage datapoints
          _datapointsCursor[_index] == _MAX_DATAPOINTS
        ) {
          // reset cursor
          _datapointsCursor[_index] = 0;
        }
        
        _datapoints[_index][_datapointsCursor[_index]] = _value;
        _datapointsCursor[_index]++;
      }

      emit IndexDataPointAdded(
        _index,
        _value
      );
    }

    /**
     * @notice Get the TWAP value from current available datapoints
     * @param _index Datapoints volatility index id {0}
     */
    function _getIndexTwap(uint256 _index) internal view returns (uint256 twap) {
      uint256 _datapointsSum;

      uint256 _datapointsLen = _datapoints[_index].length;

      for (uint256 i = 0; i < _datapointsLen; i++) {
        _datapointsSum += _datapoints[_index][i];
      }

      twap = _datapointsSum / _datapointsLen;
    }

    /**
     * @notice Get all datapoints available for a specific volatility index
     * @param _index Datapoints volatility index id {0}
     */
    function _getIndexDataPoints(uint256 _index) internal view returns (uint256[] memory datapoints) {
      datapoints = _datapoints[_index];
    }

    uint256[10] private __gap;
}

// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.11;

/**
 * @title Volmex Oracle TWAP library
 * @author volmex.finance [security@volmexlabs.com]
 */
contract TWAP {
    // Max datapoints allowed to store in
    uint8 private constant _MAX_DATAPOINTS = 180;

    // Datapoint object structure
    struct DataPoint { 
      uint256 value;
      uint256 timestamp;
    }

    // Store index datapoints into DataPoint structures array [{value: 105000000, timestamp: 1512918335}, ...]
    mapping(uint256 => DataPoint[]) private _datapoints;

    // In order to maintain low gas fees and storage efficiency we use cursors to store datapoints
    mapping(uint256 => uint256) private _datapointsCursor;

    /**
     * @notice Adds a new datapoint to the datapoints storage array
     *
     * @param _index Datapoints volatility index id {0}
     * @param _value Datapoint value to add {250000000}
     */
    function _addIndexDataPoint(uint256 _index, uint256 _value) internal {
      DataPoint memory datapoint = DataPoint(_value, block.timestamp);

      if (_datapoints[_index].length < _MAX_DATAPOINTS) {
        // initially populate available datapoint storage slots with index data
        _datapoints[_index].push(datapoint);
      } else {
        // overwrite old datapoints slots with new index data once the maximum allowed storage datapoints are reached
        if (_datapointsCursor[_index] == 0 || _datapointsCursor[_index] == _MAX_DATAPOINTS) {
          _datapointsCursor[_index] = 0;
        }
        
        _datapoints[_index][_datapointsCursor[_index]] = datapoint;
        _datapointsCursor[_index] += 1;
      }
    }

    /**
     * @notice Get the TWAP value from current available datapoints
     * @param _index Datapoints volatility index id {0}
     */
    function _getIndexTwap(uint256 _index) internal view returns (uint256 twap) {
      uint256 _datapointsSum = 0;

      for (uint256 i = 0; i < _datapoints[_index].length; i++) {
        _datapointsSum += _datapoints[_index][i].value;
      }

      twap = _datapointsSum / _datapoints[_index].length;
    }

    /**
     * @notice Get all datapoints available for a specific volatility index
     * @param _index Datapoints volatility index id {0}
     */
    function _getIndexDataPoints(uint256 _index) internal view returns (DataPoint[] memory dp) {
      dp = _datapoints[_index];
    }
}
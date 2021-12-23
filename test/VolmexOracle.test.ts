const { expect } = require('chai');
const { ethers, upgrades } = require('hardhat');
const assert = require('assert');
import { Signer } from 'ethers';
const { expectRevert } = require('@openzeppelin/test-helpers');

describe('Volmex Oracle', function () {
  let accounts: Signer[];
  let volmexOracleFactory: any;
  let volmexOracle: any;
  let volatilityIndexes: any;
  let volatilityTokenPrices: any;
  let indexes: any;
  let proofHashes: any;

  this.beforeAll(async function () {
    accounts = await ethers.getSigners();

    volmexOracleFactory = await ethers.getContractFactory('VolmexOracle');
  });

  this.beforeEach(async function () {
    volmexOracle = await upgrades.deployProxy(volmexOracleFactory, []);

    await volmexOracle.deployed();
  });

  it.only('Should deploy volmex oracle', async () => {
    const receipt = await volmexOracle.deployed();
    expect(receipt.confirmations).not.equal(0);
  });

  it.only('Should update the volatility price', async () => {
    volatilityIndexes = ['0'];
    volatilityTokenPrices = ['105000000'];
    indexes = ['0'];
    proofHashes = ['0x6c00000000000000000000000000000000000000000000000000000000000000'];
    const receipt = await volmexOracle.updateBatchVolatilityTokenPrice(
      volatilityIndexes,
      volatilityTokenPrices,
      indexes,
      proofHashes
    );
    expect((await receipt.wait()).confirmations).not.equal(0);
    let prices = await volmexOracle.getVolatilityTokenPriceByIndex('0');
    assert.equal(prices[0].toString(), '105000000');
  });

  it.only('Should not update if volatility price greater than cap ratio', async () => {
    volatilityIndexes = ['0'];
    volatilityTokenPrices = ['2105000000'];
    indexes = ['0'];
    proofHashes = ['0x6c00000000000000000000000000000000000000000000000000000000000000'];
    await expectRevert(
      volmexOracle.updateBatchVolatilityTokenPrice(
        volatilityIndexes,
        volatilityTokenPrices,
        indexes,
        proofHashes
      ),
      'VolmexOracle: _volatilityTokenPrice should be smaller than VolatilityCapRatio'
    );
  });

  it.only('should revert when length of input arrays are not equal', async () => {
    await expectRevert(
      volmexOracle.updateBatchVolatilityTokenPrice(
        ['0', '1'],
        ['105000000'],
        ['0'],
        ['0x6c00000000000000000000000000000000000000000000000000000000000000']
      ),
      'VolmexOracle: length of arrays input are not equal'
    );
  });

  it.only('should add volatility index', async () => {
    await volmexOracle.addVolatilityIndex(
      '105000000',
      '250000000',
      'ETHV3x',
      '0x6c00000000000000000000000000000000000000000000000000000000000000'
    );
    const index = await volmexOracle.volatilityIndexBySymbol('ETHV3x');
    const price = await volmexOracle.getVolatilityPriceBySymbol('ETHV3x');
    await volmexOracle.addVolatilityIndex(
      '100000000',
      '350000000',
      'ETHV4x',
      '0x6c00000000000000000000000000000000000000000000000000000000000000'
    );
    const price1 = await volmexOracle.getVolatilityPriceBySymbol('ETHV4x');
    assert.equal(price1[0].toString(), '100000000');
    assert.equal(price[0].toString(), '105000000');
    assert.equal(index, 2);
  });

  it.only('should revert when cap ratio is smaller than 1000000', async () => {
    await expectRevert(
      volmexOracle.addVolatilityIndex(
        '125000000',
        '250',
        'ETHV2x',
        '0x6c00000000000000000000000000000000000000000000000000000000000000'
      ),
      'VolmexOracle: volatility cap ratio should be greater than 1000000'
    );
  });
});

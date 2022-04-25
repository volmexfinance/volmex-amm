const { expect } = require("chai");
const { ethers, upgrades } = require("hardhat");
const assert = require("assert");
import { Signer, ContractReceipt, ContractTransaction } from "ethers";
const { expectRevert, expectEvent } = require("@openzeppelin/test-helpers");

describe("Volmex Oracle", function () {
  let owner: string;
  let accounts: Signer[];
  let volmexOracleFactory: any;
  let volmexOracle: any;
  let volatilityIndexes: any;
  let volatilityTokenPrices: any;
  let proofHashes: any;
  let protocolFactory: any;
  let protocol: any;
  let collateralFactory: any;
  let collateral: any;
  let volatilityFactory: any;
  let volatility: any;
  let inverseVolatility: any;
  let zeroAddress: any;

  this.beforeAll(async function () {
    accounts = await ethers.getSigners();

    volmexOracleFactory = await ethers.getContractFactory("VolmexOracle");

    collateralFactory = await ethers.getContractFactory("TestCollateralToken");

    volatilityFactory = await ethers.getContractFactory("VolmexPositionToken");

    protocolFactory = await ethers.getContractFactory("VolmexProtocol");
  });

  this.beforeEach(async function () {
    owner = await accounts[0].getAddress();
    collateral = await collateralFactory.deploy("VUSD", "100000000000000000000000000000000", 18);
    await collateral.deployed();

    volatility = await volatilityFactory.deploy();
    await volatility.deployed();
    let volReciept = await volatility.initialize("ETH Volatility Index", "ETHV");
    await volReciept.wait();

    inverseVolatility = await volatilityFactory.deploy();
    await inverseVolatility.deployed();
    volReciept = await inverseVolatility.initialize("Inverse ETH Volatility Index", "iETHV");
    await volReciept.wait();

    protocol = await upgrades.deployProxy(protocolFactory, [
      `${collateral.address}`,
      `${volatility.address}`,
      `${inverseVolatility.address}`,
      "25000000000000000000",
      "250",
    ]);
    await protocol.deployed();
    volmexOracle = await upgrades.deployProxy(volmexOracleFactory, [owner]);

    await volmexOracle.deployed();
  });

  it("Should deploy volmex oracle", async () => {
    const receipt = await volmexOracle.deployed();
    expect(receipt.confirmations).not.equal(0);
    assert.equal(await protocol.collateral(), collateral.address);
    assert.equal(await protocol.volatilityToken(), volatility.address);
    assert.equal(await protocol.inverseVolatilityToken(), inverseVolatility.address);
    assert.equal(await protocol.minimumCollateralQty(), "25000000000000000000");
    assert.equal(await protocol.volatilityCapRatio(), "250");
  });

  it("Should add volatility index datapoints and retrieve TWAP value", async () => {
    const volatilityIndex = "0";
    const volatilityTokenPrice1 = "105000000";
    const volatilityTokenPrice2 = "115000000";
    await volmexOracle.addIndexDataPoint(volatilityIndex, volatilityTokenPrice1);
    await volmexOracle.addIndexDataPoint(volatilityIndex, volatilityTokenPrice2);

    const datapoints = await volmexOracle.getIndexDataPoints(volatilityIndex);
    assert.equal(datapoints[0].length, 2);
    const indexTwap =  await volmexOracle.getIndexTwap(volatilityIndex);
    assert.equal(indexTwap.toString(), "110000000");
  });

  it("Should update the Batch volatility Token price", async () => {
    volatilityIndexes = ["0"];
    volatilityTokenPrices = ["105000000"];
    proofHashes = ["0x6c00000000000000000000000000000000000000000000000000000000000000"];
    const contractTx = await volmexOracle.updateBatchVolatilityTokenPrice(
      volatilityIndexes,
      volatilityTokenPrices,
      proofHashes
    );
    const contractReceipt: ContractReceipt = await contractTx.wait();
    const event = contractReceipt.events?.find(
      (event) => event.event === "BatchVolatilityTokenPriceUpdated"
    );
    const totalDataEndpoints = await volmexOracle.get
    expect((await contractTx.wait()).confirmations).not.equal(0);
    assert.equal(event?.args?._volatilityIndexes.length, 1);
    assert.equal(event?.args?._volatilityTokenPrices.length, 1);
    assert.equal(event?.args?._proofHashes.length, 1);
    let prices = await volmexOracle.getVolatilityTokenPriceByIndex("0");
    assert.equal(prices[0].toString(), "105000000");
    assert.equal(prices[1].toString(), "145000000");
  });

  it("Should not update if volatility price greater than cap ratio", async () => {
    volatilityIndexes = ["0"];
    volatilityTokenPrices = ["2105000000"];
    proofHashes = ["0x6c00000000000000000000000000000000000000000000000000000000000000"];
    await expectRevert(
      volmexOracle.updateBatchVolatilityTokenPrice(
        volatilityIndexes,
        volatilityTokenPrices,
        proofHashes
      ),
      "VolmexOracle: _volatilityTokenPrice should be smaller than VolatilityCapRatio"
    );
  });

  it("should revert when length of input arrays are not equal", async () => {
    await expectRevert(
      volmexOracle.updateBatchVolatilityTokenPrice(
        ["0", "1"],
        ["105000000"],
        ["0x6c00000000000000000000000000000000000000000000000000000000000000"]
      ),
      "VolmexOracle: length of input arrays are not equal"
    );
  });

  it("should update index by symbol", async () => {
    const contractTx: ContractTransaction = await volmexOracle.updateIndexBySymbol("ETHV", 3);
    const contractReceipt: ContractReceipt = await contractTx.wait();
    const event = contractReceipt.events?.find((event) => event.event === "SymbolIndexUpdated");
    assert.equal(event?.args?._index, 3);
    assert.equal(3, await volmexOracle.volatilityIndexBySymbol("ETHV"));
  });

  it("should add volatility index", async () => {
    protocol = await upgrades.deployProxy(protocolFactory, [
      `${collateral.address}`,
      `${volatility.address}`,
      `${inverseVolatility.address}`,
      "25000000000000000000",
      "250",
    ]);
    await protocol.deployed();
    const contractTx = await volmexOracle.addVolatilityIndex(
      "125000000",
      protocol.address,
      "ETHV2X",
      0,
      0,
      "0x6c00000000000000000000000000000000000000000000000000000000000000"
    );
    const contractReceipt: ContractReceipt = await contractTx.wait();
    const event = contractReceipt.events?.find((event) => event.event === "VolatilityIndexAdded");
    const price = await volmexOracle.getVolatilityPriceBySymbol("ETHV2X");
    const price1 = await volmexOracle.getVolatilityTokenPriceByIndex(2);
    assert.equal(event?.args?.volatilityTokenIndex, 2);
    assert.equal(event?.args?.volatilityCapRatio, 250000000);
    assert.equal(event?.args?.volatilityTokenSymbol, "ETHV2X");
    assert.equal(event?.args?.volatilityTokenPrice, 125000000);
    assert.equal(price[0].toString(), "125000000");
    assert.equal(price[1].toString(), "125000000");
    assert.equal(price1[0].toString(), "125000000");
    assert.equal(price1[1].toString(), "125000000");
  });

  it("should revert when cap ratio is smaller than 1000000", async () => {
    protocol = await upgrades.deployProxy(protocolFactory, [
      `${collateral.address}`,
      `${volatility.address}`,
      `${inverseVolatility.address}`,
      "25000000000000000000",
      "0",
    ]);
    await protocol.deployed();
    volmexOracle = await upgrades.deployProxy(volmexOracleFactory, [owner]);
    assert.equal(await protocol.collateral(), collateral.address);
    assert.equal(await protocol.volatilityToken(), volatility.address);
    assert.equal(await protocol.inverseVolatilityToken(), inverseVolatility.address);
    assert.equal(await protocol.minimumCollateralQty(), "25000000000000000000");
    await expectRevert(
      volmexOracle.addVolatilityIndex(
        0,
        protocol.address,
        "ETHV2X",
        2,
        0,
        "0x6c00000000000000000000000000000000000000000000000000000000000000"
      ),
      "VolmexOracle: volatility cap ratio should be greater than 1000000"
    );
  });

  it("should revert if protocol address is zero", async () => {
    zeroAddress = "0x0000000000000000000000000000000000000000";
    await expectRevert(
      volmexOracle.addVolatilityIndex(
        0,
        zeroAddress,
        "ETHV2X",
        2,
        0,
        "0x6c00000000000000000000000000000000000000000000000000000000000000"
      ),
      "VolmexOracle: protocol address can't be zero"
    );
  });

  it("should revert when volatility token price is greater than cap ratio", async () => {
    protocol = await upgrades.deployProxy(protocolFactory, [
      `${collateral.address}`,
      `${volatility.address}`,
      `${inverseVolatility.address}`,
      "25000000000000000000",
      "250",
    ]);
    await protocol.deployed();
    assert.equal(await protocol.collateral(), collateral.address);
    assert.equal(await protocol.volatilityToken(), volatility.address);
    assert.equal(await protocol.inverseVolatilityToken(), inverseVolatility.address);
    assert.equal(await protocol.minimumCollateralQty(), "25000000000000000000");
    await expectRevert(
      volmexOracle.addVolatilityIndex(
        "251000000",
        protocol.address,
        "ETHV2X",
        0,
        0,
        "0x6c00000000000000000000000000000000000000000000000000000000000000"
      ),
      "VolmexOracle: _volatilityTokenPrice should be smaller than VolatilityCapRatio"
    );
  });
});

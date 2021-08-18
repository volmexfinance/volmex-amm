const { expect } = require("chai");
const { ethers, upgrades } = require("hardhat");
import { Signer } from "ethers";

describe("Repricer", function () {
  let accounts: Signer[];
  let volmexOracleFactory: any;
  let volmexOracle: any;
  let repricerFactory: any;
  let repricer: any;

  this.beforeAll(async function () {
    accounts = await ethers.getSigners();

    repricerFactory = (await ethers.getContractFactory(
      "Repricer"
    ));

    volmexOracleFactory = (await ethers.getContractFactory(
      "VolmexOracle"
    ));
  });

  this.beforeEach(async function () {
    volmexOracle = await upgrades.deployProxy(volmexOracleFactory);
    await volmexOracle.deployed();

    repricer = await repricerFactory.deploy(
      "100",
      volmexOracle.address
    );
  });

  it("Should deploy repricer", async () => {
    const receipt = await repricer.deployed();
    expect(receipt.confirmations).not.equal(0);
  });

  it("Should call the reprice method", async () => {
    await volmexOracle.updateVolatilityTokenPrice(
      "ETHV",
      "100"
    );

    const receipt = await repricer.reprice(
      "1500000000000000000000",
      "14000000000000000000",
      "2000000000000000000",
      "ETHV"
    );
    await receipt.wait();

    expect(receipt.confirmations).not.equal(0);
  });
});

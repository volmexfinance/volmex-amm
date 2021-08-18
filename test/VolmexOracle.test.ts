const { expect } = require("chai");
const { ethers, upgrades } = require("hardhat");
import { Signer } from "ethers";
const { expectRevert } = require("@openzeppelin/test-helpers");


describe("Volmex Oracle", function () {
  let accounts: Signer[];
  let volmexOracleFactory: any;
  let volmexOracle: any;

  this.beforeAll(async function () {
    accounts = await ethers.getSigners();

    volmexOracleFactory = (await ethers.getContractFactory(
      "VolmexOracle"
    ));
  });

  this.beforeEach(async function () {
    volmexOracle = await upgrades.deployProxy(volmexOracleFactory);

    await volmexOracle.deployed();
  });

  it ("Should deplloy volmex oracle", async () => {
    const receipt = await volmexOracle.deployed();
    expect(receipt.confirmations).not.equal(0);
  });

  it ("Should update the volatility price", async () => {
    const receipt = await volmexOracle.updateVolatilityTokenPrice(
      "ETHV",
      "105"
    );

    expect((await receipt.wait()).confirmations).not.equal(0);

    expect(await volmexOracle.volatilityTokenPrice("ETHV")).equal("105");
  });

  it ("Should revert when volatility price is not in range", async () => {
    await expectRevert(
      volmexOracle.updateVolatilityTokenPrice(
        "ETHV",
        "250"
      ),
      "VolmexOracle: _volatilityTokenPrice should be greater than 0"
    );

    await expectRevert(
      volmexOracle.updateVolatilityTokenPrice(
        "BTCV",
        "0"
      ),
      "VolmexOracle: _volatilityTokenPrice should be greater than 0"
    );
  });
});

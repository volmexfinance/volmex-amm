const { expect } = require("chai");
const { ethers, upgrades } = require("hardhat");
import { Signer, Contract, ContractReceipt, Event } from "ethers";

import {
  TestCollateralToken,
  TestCollateralToken__factory,
  VolmexPositionToken__factory,
  VolmexProtocol,
  VolmexProtocolWithPrecision__factory,
  VolmexPositionToken,
  VolmexIndexFactory__factory,
  VolmexProtocolWithPrecisionV11__factory

} from "../typechain";
import { Result } from "@ethersproject/abi";

const { expectRevert } = require("@openzeppelin/test-helpers");

const filterEvents = (blockEvents: ContractReceipt, name: String): Array<Event> => {
  return blockEvents.events?.filter((event) => event.event === name) || [];
};

const decodeEvents = <T extends Contract>(token: T, events: Array<Event>): Array<Result> => {
  const decodedEvents = [];
  for (const event of events) {
    const getEventInterface = token.interface.getEvent(event.event || "");
    decodedEvents.push(
      token.interface.decodeEventLog(getEventInterface, event.data, event.topics)
    );
  }
  return decodedEvents;
};

describe("Volmex Protocol", function () {
  let accounts: Signer[];
  let CollateralToken: TestCollateralToken;
  let CollateralTokenFactory: TestCollateralToken__factory;
  let VolmexPositionTokenFactory: VolmexPositionToken__factory;
  let VolmexPositionToken: VolmexPositionToken;
  let VolmexProtocolFactory: VolmexProtocolWithPrecision__factory;
  let VolmexProtocol: any;
  let indexFactory: VolmexIndexFactory__factory;
  let factory: Contract;
  let positionTokenCreatedEvent: Result[];
  let VolmexProtocolV11Factory: VolmexProtocolWithPrecisionV11__factory

  this.beforeAll(async function () {
    accounts = await ethers.getSigners();
    // Deploy collateral token
    CollateralTokenFactory = (await ethers.getContractFactory(
      "TestCollateralToken"
    )) as TestCollateralToken__factory;

    VolmexPositionTokenFactory = (await ethers.getContractFactory(
      "VolmexPositionToken"
    )) as VolmexPositionToken__factory;

    VolmexProtocolFactory = (await ethers.getContractFactory(
      "VolmexProtocolWithPrecisionV1"
    )) as VolmexProtocolWithPrecision__factory;

    VolmexProtocolV11Factory = (await ethers.getContractFactory(
      "VolmexProtocolWithPrecisionV1_1"
    )) as VolmexProtocolWithPrecisionV11__factory;

    indexFactory = (await ethers.getContractFactory(
      "VolmexIndexFactory"
    )) as VolmexIndexFactory__factory;
  });

  this.beforeEach(async function () {
    CollateralToken = (await CollateralTokenFactory.deploy(
      "DAI",
      "10000000000000000000000",
      "6"
    )) as TestCollateralToken;
    await CollateralToken.deployed();

    VolmexPositionToken = (await VolmexPositionTokenFactory.deploy()) as VolmexPositionToken;

    factory = await upgrades.deployProxy(indexFactory, [VolmexPositionToken.address]);
    await factory.deployed();

    const clonedPositionTokens = await factory.createVolatilityTokens(
      "Ethereum Volatility Index Token",
      "ETHV"
    );

    const transaction = await clonedPositionTokens.wait();

    positionTokenCreatedEvent = decodeEvents(
      factory,
      filterEvents(transaction, "VolatilityTokenCreated")
    );

    VolmexProtocol = await upgrades.deployProxy(VolmexProtocolFactory, [
      CollateralToken.address,
      positionTokenCreatedEvent[0].volatilityToken,
      positionTokenCreatedEvent[0].inverseVolatilityToken,
      "25000000",
      "250",
      "1000000000000"
    ],
    {
        initializer: "initializePrecision",
    });

    await VolmexProtocol.deployed();

    const receipt = await VolmexProtocol.updateFees(10, 30);
    await receipt.wait();

    const volmexProtocolRegister = await factory.registerIndex(
      VolmexProtocol.address,
      `${process.env.COLLATERAL_TOKEN_SYMBOL}`
    );
    await volmexProtocolRegister.wait();
  });

  it("Should deploy protocol", async () => {
    expect(await VolmexProtocol.deployed());
  });

  it("Should upgrade the Protocol V1_1", async () => {
    VolmexProtocol = await upgrades.upgradeProxy(VolmexProtocol.address, VolmexProtocolV11Factory)
    await VolmexProtocol.deployed();
  })

  describe("Migrate", function () {
    let protocolFactory: any;
    let protocol: any;
    let newPositionTokenCreatedEvent: Result[];
    let v1factory: Contract;
    this.beforeAll(async () => {
      protocolFactory = await ethers.getContractFactory("VolmexProtocolWithPrecision");
    });

    this.beforeEach(async () => {
      VolmexPositionToken = (await VolmexPositionTokenFactory.deploy()) as VolmexPositionToken;

      v1factory = await upgrades.deployProxy(indexFactory, [VolmexPositionToken.address]);
      await v1factory.deployed();

      const clonedPositionTokens = await v1factory.createVolatilityTokens("VIV ETH", "VIVE");

      const transaction = await clonedPositionTokens.wait();

      newPositionTokenCreatedEvent = decodeEvents(
        v1factory,
        filterEvents(transaction, "VolatilityTokenCreated")
      );

      protocol = await upgrades.deployProxy(protocolFactory, [
        CollateralToken.address,
        newPositionTokenCreatedEvent[0].volatilityToken,
        newPositionTokenCreatedEvent[0].inverseVolatilityToken,
        "25000000",
        "400",
        "1000000000000"
      ],
      {
          initializer: "initializePrecision",
      });
      await protocol.deployed();

      const receipt = await protocol.updateFees(10, 30);
      await receipt.wait();

      const volmexProtocolRegister = await v1factory.registerIndex(
        protocol.address,
        `${process.env.COLLATERAL_TOKEN_SYMBOL}`
      );
      await volmexProtocolRegister.wait();
      VolmexProtocol = await upgrades.upgradeProxy(VolmexProtocol.address, VolmexProtocolV11Factory)
      await VolmexProtocol.deployed();
    });

    it("Should deploy protocol v2", async () => {
      expect(await protocol.deployed());
    });

    it("Should migrate to V2", async () => {
      await (
        await CollateralToken.approve(
          VolmexProtocol.address,
          "10000000000000000000000"
        )
      ).wait();
      await (await VolmexProtocol.collateralize("10000000000")).wait();

      const ethv = VolmexPositionToken.attach(positionTokenCreatedEvent[0].volatilityToken);
      const beforeBalance = await ethv.balanceOf(await accounts[0].getAddress());

      await (await VolmexProtocol.setV2Protocol(protocol.address, true, 250)).wait();

      const migrateAmount = (await ethv.balanceOf(await accounts[0].getAddress()));
      await (
        await VolmexProtocol.migrateToV2(migrateAmount)
      ).wait();

      const vive = VolmexPositionToken.attach(newPositionTokenCreatedEvent[0].volatilityToken);
      const afterBalance = await vive.balanceOf(await accounts[0].getAddress());

      const redeemedCollateral = beforeBalance.mul(await VolmexProtocol.volatilityCapRatio()).sub(
        beforeBalance
          .mul(await VolmexProtocol.volatilityCapRatio())
          .mul(await VolmexProtocol.redeemFees())
          .div(10000)
      );
      const actualConversion = redeemedCollateral
        .sub(redeemedCollateral.mul(await VolmexProtocol.issuanceFees()).div(10000))
        .div(await protocol.volatilityCapRatio());

      expect(afterBalance).to.equal(actualConversion);
    });
  });
});

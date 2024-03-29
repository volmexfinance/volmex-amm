// @ts-nocheck
const { expect } = require("chai");
const { ethers, upgrades } = require("hardhat");
import { Signer } from "ethers";

interface IProtocols {
  ETHVDAI: string | any;
  ETHVUSDC: string | any;
  BTCVDAI: string | any;
  BTCVUSDC: string | any;
}

interface IVolatility {
  ETH: string | any;
  BTC: string | any;
}

interface ICollaterals {
  DAI: string | any;
  USDC: string | any;
}

describe("VolmexController - PriceVolatility", function () {
  let accounts: Signer[];
  let owner: string;
  let volmexOracleFactory: any;
  let volmexOracle: any;
  let repricerFactory: any;
  let repricer: any;
  let poolFactory: any;
  let pools: IVolatility;
  let protocolFactory: any;
  let protocolFactoryPrecision: any;
  let protocols: IProtocols;
  let collateralFactory: any;
  let collateral: ICollaterals;
  let volatilityFactory: any;
  let volatilities: IVolatility;
  let inverseVolatilities: IVolatility;
  let controllerFactory: any;
  let controller: any;
  let poolViewFactory: any;
  let poolView: any;
  let lpHolder: string;
  let swapper1: string;
  let swapper2: string;

  const collaterals = ["DAI", "USDC"];
  const volatilitys = ["ETH", "BTC"];

  this.beforeAll(async function () {
    accounts = await ethers.getSigners();

    repricerFactory = await ethers.getContractFactory("VolmexRepricer");

    volmexOracleFactory = await ethers.getContractFactory("VolmexOracle");

    poolFactory = await ethers.getContractFactory("VolmexPool");

    collateralFactory = await ethers.getContractFactory("TestCollateralToken");

    volatilityFactory = await ethers.getContractFactory("VolmexPositionToken");

    protocolFactory = await ethers.getContractFactory("VolmexProtocol");

    protocolFactoryPrecision = await ethers.getContractFactory("VolmexProtocolWithPrecision");

    controllerFactory = await ethers.getContractFactory("VolmexController");

    poolViewFactory = await ethers.getContractFactory("VolmexPoolView");
  });

  this.beforeEach(async function () {
    await upgrades.silenceWarnings();
    protocols = {
      ETHVDAI: "",
      ETHVUSDC: "",
      BTCVDAI: "",
      BTCVUSDC: "",
    };

    collateral = {
      DAI: "",
      USDC: "",
    };

    volatilities = {
      ETH: "",
      BTC: "",
    };

    inverseVolatilities = {
      ETH: "",
      BTC: "",
    };

    pools = {
      ETH: "",
      BTC: "",
    };

    for (let col of collaterals) {
      const initSupply =
        col == "DAI" ? "100000000000000000000000000000000" : "100000000000000000000";
      const decimals = col == "DAI" ? 18 : 6;
      collateral[col] = await collateralFactory.deploy(col, initSupply, decimals);
      await collateral[col].deployed();
    }

    for (let vol of volatilitys) {
      volatilities[vol] = await volatilityFactory.deploy();
      await volatilities[vol].deployed();
      await (await volatilities[vol].initialize(`${vol} Volatility Index`, `${vol}V`)).wait();

      inverseVolatilities[vol] = await volatilityFactory.deploy();
      await inverseVolatilities[vol].deployed();
      await (
        await inverseVolatilities[vol].initialize(`Inverse ${vol} Volatility Index`, `i${vol}V`)
      ).wait();

      const type = `${vol}V${collaterals[0]}`;
      protocols[type] = await upgrades.deployProxy(protocolFactory, [
        `${collateral[collaterals[0]].address}`,
        `${volatilities[vol].address}`,
        `${inverseVolatilities[vol].address}`,
        "25000000000000000000",
        "250",
      ]);
      await protocols[type].deployed();
      await (await protocols[type].updateFees("10", "30")).wait();

      const VOLMEX_PROTOCOL_ROLE =
        "0x33ba6006595f7ad5c59211bde33456cab351f47602fc04f644c8690bc73c4e16";

      await (
        await volatilities[vol].grantRole(VOLMEX_PROTOCOL_ROLE, `${protocols[type].address}`)
      ).wait();
      await (
        await inverseVolatilities[vol].grantRole(
          VOLMEX_PROTOCOL_ROLE,
          `${protocols[type].address}`
        )
      ).wait();
    }

    for (let vol of volatilitys) {
      const type = `${vol}V${collaterals[1]}`;

      protocols[type] = await upgrades.deployProxy(
        protocolFactoryPrecision,
        [
          `${collateral[collaterals[1]].address}`,
          `${volatilities[vol].address}`,
          `${inverseVolatilities[vol].address}`,
          "25000000",
          "250",
          "1000000000000",
        ],
        {
          initializer: "initializePrecision",
        }
      );
      await protocols[type].deployed();
      await (await protocols[type].updateFees("10", "30")).wait();
      const VOLMEX_PROTOCOL_ROLE =
        "0x33ba6006595f7ad5c59211bde33456cab351f47602fc04f644c8690bc73c4e16";

      await (
        await volatilities[vol].grantRole(VOLMEX_PROTOCOL_ROLE, `${protocols[type].address}`)
      ).wait();
      await (
        await inverseVolatilities[vol].grantRole(
          VOLMEX_PROTOCOL_ROLE,
          `${protocols[type].address}`
        )
      ).wait();
    }
    owner = await accounts[0].getAddress();

    volmexOracle = await upgrades.deployProxy(volmexOracleFactory, [owner]);
    await volmexOracle.deployed();

    repricer = await upgrades.deployProxy(repricerFactory, [volmexOracle.address, owner]);
    await repricer.deployed();

    const baseFee = (0.02 * Math.pow(10, 18)).toString();
    const maxFee = (0.4 * Math.pow(10, 18)).toString();
    const feeAmpPrimary = 10;
    const feeAmpComplement = 10;
    owner = await accounts[0].getAddress();
    lpHolder = accounts[1];
    swapper1 = accounts[2];
    swapper2 = accounts[3];

    const qMin = (1 * Math.pow(10, 6)).toString();
    const pMin = (0.01 * Math.pow(10, 18)).toString();
    const exposureLimitPrimary = (0.25 * Math.pow(10, 18)).toString();
    const exposureLimitComplement = (0.25 * Math.pow(10, 18)).toString();
    const leveragePrimary = "999996478162223000";
    const leverageComplement = "1000003521850180000";
    const MAX = "100000000000000000000000000000000";

    for (let vol of volatilitys) {
      const type = `${vol}V${collaterals[0]}`;

      pools[vol] = await upgrades.deployProxy(
        poolFactory,
        [
          repricer.address,
          protocols[type].address,
          volatilitys.indexOf(vol),
          baseFee,
          maxFee,
          feeAmpPrimary,
          feeAmpComplement,
          owner,
        ],
        {
          initializer: "initialize",
        }
      );
      await pools[vol].deployed();

      await (await collateral["DAI"].mint(owner, MAX)).wait();
      await (await collateral["DAI"].approve(protocols[type].address, MAX)).wait();
      await (await protocols[type].collateralize(MAX)).wait();
    }

    let controllerParam = {
      collaterals: [],
      pools: [],
      protocols: [],
    };
    Object.values(collateral).forEach((coll) => {
      controllerParam.collaterals.push(coll.address);
    });
    Object.values(pools).forEach((pool) => {
      controllerParam.pools.push(pool.address);
    });
    Object.values(protocols).forEach((protocol) => {
      controllerParam.protocols.push(protocol.address);
    });

    controller = await upgrades.deployProxy(controllerFactory, [
      controllerParam.collaterals,
      controllerParam.pools,
      controllerParam.protocols,
      owner,
    ]);
    await controller.deployed();

    await (await pools["ETH"].setController(controller.address)).wait();
    await (await pools["BTC"].setController(controller.address)).wait();

    await (await volatilities["ETH"].approve(controller.address, "1000000000000000000")).wait();
    await (
      await inverseVolatilities["ETH"].approve(controller.address, "1000000000000000000")
    ).wait();
    await (await volatilities["BTC"].approve(controller.address, "1000000000000000000")).wait();
    await (
      await inverseVolatilities["BTC"].approve(controller.address, "1000000000000000000")
    ).wait();

    await (
      await controller.finalizePool(
        0,
        "1000000000000000000",
        leveragePrimary,
        "1000000000000000000",
        leverageComplement,
        exposureLimitPrimary,
        exposureLimitComplement,
        pMin,
        qMin
      )
    ).wait();

    await (
      await controller.finalizePool(
        1,
        "1000000000000000000",
        leveragePrimary,
        "1000000000000000000",
        leverageComplement,
        exposureLimitPrimary,
        exposureLimitComplement,
        pMin,
        qMin
      )
    ).wait();

    poolView = await upgrades.deployProxy(poolViewFactory, [controller.address]);
    await poolView.deployed();
  });

  it("should deploy controller", async () => {
    const controllerReceipt = await controller.deployed();
    expect(controllerReceipt.confirmations).not.equal(0);
  });

  describe("Variable Oracle 1 to 250", function () {
    let lp: string;
    let swap1: string;
    let swap2: string;
    let volatilityIndex: number = 1;
    this.beforeEach(async () => {
      const collateralTokens = "100000000000000000000000000000000000000";
      const volatilityTokens = "100000000000000000000000000000000000000";

      lp = await lpHolder.getAddress();
      swap1 = await swapper1.getAddress();
      swap2 = await swapper2.getAddress();

      await (await collateral["DAI"].mint(lp, collateralTokens)).wait();
      await (
        await collateral["DAI"]
          .connect(lpHolder)
          .approve(protocols["ETHVDAI"].address, volatilityTokens)
      ).wait();
      await (await protocols["ETHVDAI"].connect(lpHolder).collateralize(volatilityTokens)).wait();

      await (await collateral["DAI"].mint(swap1, collateralTokens)).wait();

      await (
        await collateral["DAI"]
          .connect(swapper1)
          .approve(protocols["ETHVDAI"].address, volatilityTokens)
      ).wait();
      await (await protocols["ETHVDAI"].connect(swapper1).collateralize(volatilityTokens)).wait();

      await (await collateral["DAI"].mint(swap2, collateralTokens)).wait();
      await (
        await collateral["DAI"]
          .connect(swapper2)
          .approve(protocols["ETHVDAI"].address, volatilityTokens)
      ).wait();
      await (await protocols["ETHVDAI"].connect(swapper2).collateralize(volatilityTokens)).wait();

      const poolAmountOut = "2000000000000000000000000";
      const amountsIn = await poolView.getTokensToJoin(pools["ETH"].address, poolAmountOut);
      await (
        await volatilities["ETH"]
          .connect(lpHolder)
          .approve(controller.address, amountsIn[0].toString())
      ).wait();
      await (
        await inverseVolatilities["ETH"]
          .connect(lpHolder)
          .approve(controller.address, amountsIn[0].toString())
      ).wait();

      const add = await controller
        .connect(lpHolder)
        .addLiquidity(poolAmountOut, [amountsIn[0].toString(), amountsIn[0].toString()], "0");
      await add.wait();

      let volatilityIndexes = ["0"];
      let volatilityTokenPrices = [volatilityIndex.toString() + "000000"];
      //   console.log(volatilityTokenPrices, "volatilityTokenPrices");
      let proofHashes = ["0x6c00000000000000000000000000000000000000000000000000000000000000"];
      await (
        await volmexOracle.updateBatchVolatilityTokenPrice(
          volatilityIndexes,
          volatilityTokenPrices,
          proofHashes
        )
      ).wait();
    });

    for (let index = 1; index <= 250; index++) {
      it(`Call swaps for all oracle prices till 101 to 200`, async () => {
        console.log("Oracle price", (await volmexOracle.getIndexTwap(0)).toString());
        const amountOut = await pools["ETH"]
          .connect(swapper1)
          .getTokenAmountOut(volatilities["ETH"].address, "1000000000000000000");

        await (
          await volatilities["ETH"]
            .connect(swapper1)
            .approve(controller.address, "1000000000000000000")
        ).wait();

        (
          await controller
            .connect(swapper1)
            .swap(
              0,
              volatilities["ETH"].address,
              "1000000000000000000",
              inverseVolatilities["ETH"].address,
              amountOut[0]
            )
        ).wait();

        await (await pools["ETH"].reprice()).wait();
        const volAmount = await poolView
          .connect(swapper1)
          .getCollateralToVolatility("250000000000000000000", volatilities["ETH"].address, [0, 0]);

        await (
          await collateral["DAI"]
            .connect(swapper1)
            .approve(controller.address, "250000000000000000000")
        ).wait();
        await (
          await collateral["DAI"].mint(swap1, "100000000000000000000000000000000000000")
        ).wait();

        (
          await controller
            .connect(swapper1)
            .swapCollateralToVolatility(
              ["250000000000000000000", "1000000000000000"],
              inverseVolatilities["ETH"].address,
              [0, 0]
            )
        ).wait();

        await (await pools["ETH"].reprice()).wait();
        const colAmount = await poolView
          .connect(swapper1)
          .getVolatilityToCollateral(volatilities["ETH"].address, "1000000000000000000", [0, 0]);

        await (
          await volatilities["ETH"]
            .connect(swapper1)
            .approve(controller.address, "1000000000000000000")
        ).wait();

        (
          await controller
            .connect(swapper1)
            .swapVolatilityToCollateral(
              ["1000000000000000000", "75487850658328461"],
              ["0", "0"],
              volatilities["ETH"].address
            )
        ).wait();

        volatilityIndex = index;
      });
    }
  });

  describe("Swaps, liquidity - add & remove", function () {
    let lp: string;
    let swap1: string;
    let swap2: string;
    this.beforeEach(async () => {
      const collateralTokens = "100000000000000000000000000000000";
      const volatilityTokens = "100000000000000000000000000";

      lp = await lpHolder.getAddress();
      swap1 = await swapper1.getAddress();
      swap2 = await swapper2.getAddress();

      await (await collateral["DAI"].mint(lp, collateralTokens)).wait();
      await (
        await collateral["DAI"]
          .connect(lpHolder)
          .approve(protocols["ETHVDAI"].address, volatilityTokens)
      ).wait();
      await (
        await collateral["DAI"]
          .connect(lpHolder)
          .approve(protocols["BTCVDAI"].address, volatilityTokens)
      ).wait();
      await (await protocols["ETHVDAI"].connect(lpHolder).collateralize(volatilityTokens)).wait();
      await (await protocols["BTCVDAI"].connect(lpHolder).collateralize(volatilityTokens)).wait();

      await (await collateral["DAI"].mint(swap1, collateralTokens)).wait();
      await (
        await collateral["DAI"]
          .connect(swapper1)
          .approve(protocols["ETHVDAI"].address, volatilityTokens)
      ).wait();
      await (
        await collateral["DAI"]
          .connect(swapper1)
          .approve(protocols["BTCVDAI"].address, volatilityTokens)
      ).wait();
      await (await protocols["ETHVDAI"].connect(swapper1).collateralize(volatilityTokens)).wait();
      await (await protocols["BTCVDAI"].connect(swapper1).collateralize(volatilityTokens)).wait();

      await (await collateral["DAI"].mint(swap2, collateralTokens)).wait();
      await (
        await collateral["DAI"]
          .connect(swapper2)
          .approve(protocols["ETHVDAI"].address, volatilityTokens)
      ).wait();
      await (
        await collateral["DAI"]
          .connect(swapper2)
          .approve(protocols["BTCVDAI"].address, volatilityTokens)
      ).wait();
      await (await protocols["ETHVDAI"].connect(swapper2).collateralize(volatilityTokens)).wait();
      await (await protocols["BTCVDAI"].connect(swapper2).collateralize(volatilityTokens)).wait();
    });

    it("Should swap volatility to collateral", async () => {
      let volatilityIndexes = ["0"];
      let volatilityTokenPrices = ["140000000"];
      let proofHashes = ["0x6c00000000000000000000000000000000000000000000000000000000000000"];
      await (
        await volmexOracle.updateBatchVolatilityTokenPrice(
          volatilityIndexes,
          volatilityTokenPrices,
          proofHashes
        )
      ).wait();
      const poolAmountOut = "2000000000000000000000000";
      const amountsIn = await poolView.getTokensToJoin(pools["ETH"].address, poolAmountOut);
      await (
        await volatilities["ETH"]
          .connect(lpHolder)
          .approve(controller.address, amountsIn[0].toString())
      ).wait();
      await (
        await inverseVolatilities["ETH"]
          .connect(lpHolder)
          .approve(controller.address, amountsIn[0].toString())
      ).wait();
      const add = await controller
        .connect(lpHolder)
        .addLiquidity(poolAmountOut, [amountsIn[0].toString(), amountsIn[0].toString()], "0");
      await add.wait();
      const amountOut = await pools["ETH"]
        .connect(swapper2)
        .getTokenAmountOut(inverseVolatilities["ETH"].address, "100000000000000000000");
      await (
        await inverseVolatilities["ETH"]
          .connect(swapper2)
          .approve(controller.address, "100000000000000000000")
      ).wait();
      await (
        await volatilities["ETH"]
          .connect(swapper2)
          .approve(controller.address, "5000000000000000000000")
      ).wait();

      await (await pools["ETH"].reprice()).wait();
      const colAmount = await poolView
        .connect(swapper1)
        .getVolatilityToCollateral(volatilities["ETH"].address, "100000000000000000000", [0, 0]);
      await (
        await volatilities["ETH"]
          .connect(swapper1)
          .approve(controller.address, "1000000000000000000000")
      ).wait();
      const collateralBefore = await collateral["DAI"].balanceOf(swap1);

      const swap = await controller
        .connect(swapper1)
        .swapVolatilityToCollateral(
          ["100000000000000000000", colAmount[0].toString()],
          ["0", "0"],
          volatilities["ETH"].address
        );
      const { events } = await swap.wait();
      const collateralAfter = await collateral["DAI"].balanceOf(swap1);

      const changedBalance = collateralAfter.sub(collateralBefore);

      const logData = getEventLog(events, "CollateralSwapped", [
        "uint256",
        "uint256",
        "uint256",
        "uint256",
      ]);

      expect(Number(changedBalance.toString())).to.equal(Number(logData[1].toString()));
    });

    it("Should swap volatility to collateral when oracle price is 70", async () => {
      let volatilityIndexes = ["0"];
      let volatilityTokenPrices = ["70000000"];
      let proofHashes = ["0x6c00000000000000000000000000000000000000000000000000000000000000"];
      await (
        await volmexOracle.updateBatchVolatilityTokenPrice(
          volatilityIndexes,
          volatilityTokenPrices,
          proofHashes
        )
      ).wait();
      const poolAmountOut = "2000000000000000000000000";
      const amountsIn = await poolView.getTokensToJoin(pools["ETH"].address, poolAmountOut);
      await (
        await volatilities["ETH"]
          .connect(lpHolder)
          .approve(controller.address, amountsIn[0].toString())
      ).wait();
      await (
        await inverseVolatilities["ETH"]
          .connect(lpHolder)
          .approve(controller.address, amountsIn[0].toString())
      ).wait();
      const add = await controller
        .connect(lpHolder)
        .addLiquidity(poolAmountOut, [amountsIn[0].toString(), amountsIn[0].toString()], "0");
      await add.wait();
      await (
        await inverseVolatilities["ETH"]
          .connect(swapper2)
          .approve(controller.address, "100000000000000000000")
      ).wait();
      await (
        await volatilities["ETH"]
          .connect(swapper2)
          .approve(controller.address, "5000000000000000000000")
      ).wait();

      await (await pools["ETH"].reprice()).wait();
      const colAmount = await poolView
        .connect(swapper1)
        .getVolatilityToCollateral(volatilities["ETH"].address, "100000000000000000000", [0, 0]);
      await (
        await volatilities["ETH"]
          .connect(swapper1)
          .approve(controller.address, "1000000000000000000000")
      ).wait();
      const collateralBefore = await collateral["DAI"].balanceOf(swap1);

      const swap = await controller
        .connect(swapper1)
        .swapVolatilityToCollateral(
          ["100000000000000000000", colAmount[0].toString()],
          ["0", "0"],
          volatilities["ETH"].address
        );
      const { events } = await swap.wait();
      const collateralAfter = await collateral["DAI"].balanceOf(swap1);

      const changedBalance = collateralAfter.sub(collateralBefore);

      const logData = getEventLog(events, "CollateralSwapped", [
        "uint256",
        "uint256",
        "uint256",
        "uint256",
      ]);
      expect(Number(changedBalance.toString())).to.equal(Number(logData[1].toString()));
    });
  });
});

const getEventLog = (events: any[], eventName: string, params: string[]): any => {
  let data;
  events.forEach((log: any) => {
    if (log["event"] == eventName) {
      data = log["data"];
    }
  });
  const logData = ethers.utils.defaultAbiCoder.decode(params, data);
  return logData;
};

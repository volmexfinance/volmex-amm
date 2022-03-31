const { expect } = require("chai");
const { ethers, upgrades } = require("hardhat");
import { Signer } from "ethers";
const { expectRevert, time } = require("@openzeppelin/test-helpers");

describe("VolmexPool", function () {
  let accounts: Signer[];
  let owner: string;
  let volmexOracleFactory: any;
  let volmexOracle: any;
  let repricerFactory: any;
  let repricer: any;
  let poolFactory: any;
  let pool: any;
  let protocolFactory: any;
  let protocol: any;
  let collateralFactory: any;
  let collateral: any;
  let volatilityFactory: any;
  let volatility: any;
  let inverseVolatility: any;
  let zeroAddress: any;
  let protocolFactoryPrecision: any;

  this.beforeAll(async function () {
    accounts = await ethers.getSigners();

    repricerFactory = await ethers.getContractFactory("VolmexRepricer");

    volmexOracleFactory = await ethers.getContractFactory("VolmexOracle");

    poolFactory = await ethers.getContractFactory("VolmexPoolMock");

    collateralFactory = await ethers.getContractFactory("TestCollateralToken");

    volatilityFactory = await ethers.getContractFactory("VolmexPositionToken");

    protocolFactory = await ethers.getContractFactory("VolmexProtocol");

    protocolFactoryPrecision = await ethers.getContractFactory("VolmexProtocolWithPrecision");
  });

  this.beforeEach(async function () {
    owner = await accounts[0].getAddress();
    await upgrades.silenceWarnings();
    collateral = await collateralFactory.deploy("VUSD", "100000000000000000000000000000000", 18);
    await collateral.deployed();

    volatility = await volatilityFactory.deploy();
    await volatility.deployed();
    let volreceipt = await volatility.initialize("ETH Volatility Index", "ETHV");
    await volreceipt.wait();

    inverseVolatility = await volatilityFactory.deploy();
    await inverseVolatility.deployed();
    volreceipt = await inverseVolatility.initialize("Inverse ETH Volatility Index", "iETHV");
    await volreceipt.wait();

    protocol = await upgrades.deployProxy(protocolFactory, [
      `${collateral.address}`,
      `${volatility.address}`,
      `${inverseVolatility.address}`,
      "25000000000000000000",
      "250",
    ]);
    await protocol.deployed();
    await (await protocol.updateFees("10", "30")).wait();

    const VOLMEX_PROTOCOL_ROLE =
      "0x33ba6006595f7ad5c59211bde33456cab351f47602fc04f644c8690bc73c4e16";

    volreceipt = await volatility.grantRole(VOLMEX_PROTOCOL_ROLE, `${protocol.address}`);
    await volreceipt.wait();

    volreceipt = await inverseVolatility.grantRole(VOLMEX_PROTOCOL_ROLE, `${protocol.address}`);
    await volreceipt.wait();

    volmexOracle = await upgrades.deployProxy(volmexOracleFactory, [owner]);
    await volmexOracle.deployed();

    repricer = await upgrades.deployProxy(repricerFactory, [volmexOracle.address]);
    await repricer.deployed();

    const baseFee = (0.02 * Math.pow(10, 18)).toString();
    const maxFee = (0.4 * Math.pow(10, 18)).toString();
    const feeAmpPrimary = 10;
    const feeAmpComplement = 10;

    pool = await upgrades.deployProxy(poolFactory, [
      repricer.address,
      protocol.address,
      "0",
      baseFee,
      maxFee,
      feeAmpPrimary,
      feeAmpComplement,
      owner
    ]);
    await pool.deployed();
    await (await pool.setControllerWithoutCheck(owner)).wait();

    const qMin = (1 * Math.pow(10, 6)).toString();
    const pMin = (0.01 * Math.pow(10, 18)).toString();
    const exposureLimitPrimary = (0.25 * Math.pow(10, 18)).toString();
    const exposureLimitComplement = (0.25 * Math.pow(10, 18)).toString();
    const leveragePrimary = "999996478162223000";
    const leverageComplement = "1000003521850180000";
    const MAX = "1000000000000000000000000000";

    await (await collateral.mint(owner, MAX)).wait();
    await (await collateral.approve(protocol.address, MAX)).wait();
    await (await protocol.collateralize(MAX)).wait();

    await (await volatility.approve(pool.address, "1000000000000000000")).wait();
    await (await inverseVolatility.approve(pool.address, "1000000000000000000")).wait();

    await expectRevert(
      pool.finalize(
        "1000000000000000000",
        leveragePrimary,
        "10000000000000000000",
        leverageComplement,
        exposureLimitPrimary,
        exposureLimitComplement,
        pMin,
        qMin,
        owner
      ),
      "VolmexPool: Assets balance should be same"
    );

    const finalizeReceipt = await pool.finalize(
      "1000000000000000000",
      leveragePrimary,
      "1000000000000000000",
      leverageComplement,
      exposureLimitPrimary,
      exposureLimitComplement,
      pMin,
      qMin,
      owner
    );
    await finalizeReceipt.wait();
  });

  describe("Initialize", () => {
    let baseFee: any;
    let maxFee: any;
    let feeAmpPrimary: any;
    let feeAmpComplement: any;
    let qMin: any;
    let pMin: any;
    let exposureLimitPrimary: any;
    let exposureLimitComplement: any;
    let leveragePrimary: any;
    let leverageComplement: any;
    zeroAddress = "0x0000000000000000000000000000000000000000";

    this.beforeEach(async () => {
      baseFee = (0.02 * Math.pow(10, 18)).toString();
      maxFee = (0.4 * Math.pow(10, 18)).toString();
      feeAmpPrimary = 10;
      feeAmpComplement = 10;
      qMin = (1 * Math.pow(10, 6)).toString();
      pMin = (0.01 * Math.pow(10, 18)).toString();
      exposureLimitPrimary = (0.25 * Math.pow(10, 18)).toString();
      exposureLimitComplement = (0.25 * Math.pow(10, 18)).toString();
      leveragePrimary = "999996478162223000";
      leverageComplement = "1000003521850180000";
    });

    it("Unsupported repricer", async () => {
      await expectRevert(
        upgrades.deployProxy(poolFactory, [
          volmexOracle.address,
          protocol.address,
          0,
          baseFee,
          maxFee,
          feeAmpPrimary,
          feeAmpComplement,
          owner
        ]),
        "VolmexPool: Repricer does not supports interface"
      );
    });

    it("Unsupported protocol", async () => {
      await expectRevert(
        upgrades.deployProxy(poolFactory, [
          repricer.address,
          zeroAddress,
          0,
          baseFee,
          maxFee,
          feeAmpPrimary,
          feeAmpComplement,
          owner
        ]),
        "VolmexPool: protocol address can't be zero"
      );
    });

    it("base fee revert", async () => {
      pool = await upgrades.deployProxy(poolFactory, [
        repricer.address,
        protocol.address,
        0,
        0,
        maxFee,
        feeAmpPrimary,
        feeAmpComplement,
        owner
      ]);
      await pool.deployed();
      await (await pool.setControllerWithoutCheck(owner)).wait();

      await expectRevert(
        pool.finalize(
          "1000000000000000000",
          leveragePrimary,
          "1000000000000000000",
          leverageComplement,
          exposureLimitPrimary,
          exposureLimitComplement,
          pMin,
          qMin,
          owner
        ),
        "VolmexPool: baseFee should be larger than 0"
      );
    });

    it("USDC collateral", async () => {
      const collateralUSDC = await collateralFactory.deploy("USDC", "10000000000000", 6);
      await collateralUSDC.deployed();
      const precision = await upgrades.deployProxy(
        protocolFactoryPrecision,
        [
          `${collateralUSDC.address}`,
          `${volatility.address}`,
          `${inverseVolatility.address}`,
          "25000000",
          "250",
          "1000000000000",
        ],
        {
          initializer: "initializePrecision",
        }
      );
      await precision.deployed();

      const pool = await upgrades.deployProxy(poolFactory, [
        repricer.address,
        precision.address,
        "1",
        baseFee,
        maxFee,
        feeAmpPrimary,
        feeAmpComplement,
        owner
      ]);
      await pool.deployed();
      await (await pool.setControllerWithoutCheck(owner)).wait();

      const MAX = "1000000000000000000000000";
      await (await collateral.mint(owner, MAX)).wait();
      await (await collateral.approve(protocol.address, MAX)).wait();
      await (await protocol.collateralize(MAX)).wait();

      await (await volatility.approve(pool.address, "1000000000000000000")).wait();
      await (await inverseVolatility.approve(pool.address, "1000000000000000000")).wait();

      await (
        await pool.finalize(
          "1000000000000000000",
          leveragePrimary,
          "1000000000000000000",
          leverageComplement,
          exposureLimitPrimary,
          exposureLimitComplement,
          pMin,
          qMin,
          owner
        )
      ).wait();
    });
  });

  describe("Pool Methods", () => {
    it("should deploy pool", async () => {
      const poolreceipt = await pool.deployed();
      expect(poolreceipt.confirmations).not.equal(0);
    });

    it("Should update the admin fee", async () => {
      await (await pool.updateAdminFee(70)).wait();
      expect(await pool.adminFee()).to.equal(70);
      await expectRevert(
        pool.updateAdminFee(10001),
        "VolmexPool: _fee should be smaller than 10000"
      );
    });

    it("Should update volatility index", async () => {
      await (await pool.updateVolatilityIndex(2)).wait();
      expect(await pool.volatilityIndex()).to.equal(2);
    });

    it("Should add liquidity", async () => {
      await (await volatility.approve(pool.address, "30000000000000000000")).wait();
      await (await inverseVolatility.approve(pool.address, "30000000000000000000")).wait();

      const balanceBefore = await volatility.balanceOf(owner);

      const join = await pool.joinPool(
        "7000000000000000000000",
        ["30000000000000000000", "30000000000000000000"],
        owner
      );
      const { events } = await join.wait();

      const balanceAfter = await volatility.balanceOf(owner);

      let data;
      events.forEach((log: any) => {
        if (log["event"] == "Joined") {
          data = log["data"];
        }
      });
      const logData = ethers.utils.defaultAbiCoder.decode(["uint256"], data);
      const changedBalance = balanceBefore.sub(balanceAfter);
      expect(Number(changedBalance.toString())).to.equal(Number(logData[0].toString()));
    });

    it("Should remove liquidity", async () => {
      await (await volatility.approve(pool.address, "30000000000000000000")).wait();
      await (await inverseVolatility.approve(pool.address, "30000000000000000000")).wait();

      const join = await pool.joinPool(
        "7000000000000000000000",
        ["30000000000000000000", "30000000000000000000"],
        owner
      );
      await join.wait();

      const balanceBefore = await volatility.balanceOf(owner);

      const exit = await pool.exitPool(
        "700000000000000000000",
        ["2700000000000000000", "2700000000000000000"],
        owner
      );
      const { events } = await exit.wait();

      const balanceAfter = await volatility.balanceOf(owner);

      let data;
      events.forEach((log: any) => {
        if (log["event"] == "Exited") {
          data = log["data"];
        }
      });
      const logData = ethers.utils.defaultAbiCoder.decode(["uint256"], data);
      const changedBalance = balanceAfter.sub(balanceBefore);
      expect(Number(changedBalance.toString())).to.equal(Number(logData[0].toString()));
    });

    it("Should swap the token", async () => {
      await (await volatility.approve(pool.address, "38960000000000000000")).wait();
      await (await inverseVolatility.approve(pool.address, "38960000000000000000")).wait();

      const join = await pool.joinPool(
        "7000000000000000000000",
        ["38960000000000000000", "38960000000000000000"],
        owner
      );
      await join.wait();

      const amountOut = await pool.getTokenAmountOut(volatility.address, "5960000000000000000");

      await (await volatility.approve(pool.address, "5960000000000000000")).wait();
      // await (await inverseVolatility.approve(pool.address, "38960000000000000000")).wait();

      const balanceBefore = await inverseVolatility.balanceOf(owner);
      const swap = await pool.swapExactAmountIn(
        volatility.address,
        "5960000000000000000",
        inverseVolatility.address,
        amountOut[0].toString(),
        owner,
        false
      );
      const { events } = await swap.wait();
      const balanceAfter = await inverseVolatility.balanceOf(owner);

      let data;
      events.forEach((log: any) => {
        if (log["event"] == "Swapped") {
          data = log["data"];
        }
      });
      const logData = ethers.utils.defaultAbiCoder.decode(
        ["uint256", "uint256", "uint256", "uint256", "uint256", "uint256", "uint256"],
        data
      );

      expect(Number(balanceAfter.sub(balanceBefore))).to.equal(Number(logData[1].toString()));
    });

    it("Should update reprice", async () => {
      await (await volatility.approve(pool.address, "38960000000000000000")).wait();
      await (await inverseVolatility.approve(pool.address, "38960000000000000000")).wait();

      const test = await pool.joinPool(
        "7000000000000000000000",
        ["38960000000000000000", "38960000000000000000"],
        owner
      );
      await test.wait();

      const latest = await time.latestBlock();
      await (await inverseVolatility.approve(pool.address, "3000000000000000000")).wait();

      let amountOut = await pool.getTokenAmountOut(
        inverseVolatility.address,
        "3000000000000000000"
      );

      let swap = await pool.swapExactAmountIn(
        inverseVolatility.address,
        "3000000000000000000",
        volatility.address,
        "1000000000000000000",
        owner,
        false
      );
      let swapreceipt = await swap.wait();

      amountOut = await pool.getTokenAmountOut(inverseVolatility.address, "3000000000000000000");

      await time.advanceBlockTo(parseInt(latest) + 5);
      const current = await time.latestBlock();

      amountOut = await pool.getTokenAmountOut(inverseVolatility.address, "3000000000000000000");

      await (await inverseVolatility.approve(pool.address, "3000000000000000000")).wait();

      const swap2 = await pool.swapExactAmountIn(
        inverseVolatility.address,
        "3000000000000000000",
        volatility.address,
        "1000000000000000000",
        owner,
        false
      );
      await swap.wait();
    });

    it("should swap the assets", async () => {
      await (await volatility.approve(pool.address, "20000000000000000000")).wait();
      await (await inverseVolatility.approve(pool.address, "20000000000000000000")).wait();
      const joinReceipt = await pool.joinPool(
        "3000000000000000000000",
        ["20000000000000000000", "20000000000000000000"],
        owner
      );
      await joinReceipt.wait();
      await (await volatility.approve(pool.address, "3000000000000000000")).wait();

      const swap = await pool.swapExactAmountIn(
        volatility.address,
        "3000000000000000000",
        inverseVolatility.address,
        "1000000000000000000",
        owner,
        false
      );
      const swapreceipt = await swap.wait();
      expect(swapreceipt.confirmations).equal(1);
    });

    it("Should user exit liquidity from pool", async () => {
      await (await volatility.approve(pool.address, "20000000000000000000")).wait();
      await (await inverseVolatility.approve(pool.address, "20000000000000000000")).wait();
      const joinReceipt = await pool.joinPool(
        "3000000000000000000000",
        ["20000000000000000000", "20000000000000000000"],
        owner
      );
      await joinReceipt.wait();

      const exitReceipt = await pool.exitPool(
        "1000000000000000000000",
        ["1000000000000000000", "1000000000000000000"],
        owner
      );
      await exitReceipt.wait();
    });

    it("Should volatility tokens", async () => {
      expect(await pool.tokens(0)).to.equal(await protocol.volatilityToken());
      expect(await pool.tokens(1)).to.equal(await protocol.inverseVolatilityToken());
    });

    it("Should return the token leverage", async () => {
      let receipt = await pool.getLeverage(await protocol.volatilityToken());
      expect(await receipt).not.equal(0);

      receipt = await pool.getLeverage(await protocol.inverseVolatilityToken());
      expect(await receipt).not.equal(0);
    });

    it("Should return the reserve of token", async () => {
      let receipt = await pool.getBalance(await protocol.volatilityToken());
      expect(await receipt).not.equal(0);

      receipt = await pool.getBalance(await protocol.inverseVolatilityToken());
      expect(await receipt).not.equal(0);
    });

    it("Should pause/unpause the tokens", async () => {
      let receipt = await pool.togglePause(true);
      expect(receipt.confirmations).equal(1);

      receipt = await pool.togglePause(false);
      expect(receipt.confirmations).equal(1);
    });

    it("Should check the pool is finalized", async () => {
      let receipt = await pool.finalized();
      expect(receipt).to.be.true;
    });

    it("Should not finalized if balances are not same", async () => {
      const qMin = (1 * Math.pow(10, 6)).toString();
      const pMin = (0.01 * Math.pow(10, 18)).toString();
      const exposureLimitPrimary = (0.25 * Math.pow(10, 18)).toString();
      const exposureLimitComplement = (0.25 * Math.pow(10, 18)).toString();
      const leveragePrimary = "999996478162223000";
      const leverageComplement = "1000003521850180000";
      const MAX = "10000000000000000000000";
      await expectRevert.unspecified(
        pool.finalize(
          "100000000000000000000",
          leveragePrimary,
          "1000000000000000000",
          leverageComplement,
          exposureLimitPrimary,
          exposureLimitComplement,
          pMin,
          qMin,
          owner
        )
      );
    });

    it("Should not finalized if pool is already finalized", async () => {
      const qMin = (1 * Math.pow(10, 6)).toString();
      const pMin = (0.01 * Math.pow(10, 18)).toString();
      const exposureLimitPrimary = (0.25 * Math.pow(10, 18)).toString();
      const exposureLimitComplement = (0.25 * Math.pow(10, 18)).toString();
      const leveragePrimary = "999996478162223000";
      const leverageComplement = "1000003521850180000";
      const MAX = "10000000000000000000000";
      await expectRevert(
        pool.finalize(
          "1000000000000000000",
          leveragePrimary,
          "1000000000000000000",
          leverageComplement,
          exposureLimitPrimary,
          exposureLimitComplement,
          pMin,
          qMin,
          owner
        ),
        "VolmexPool: Pool is finalized"
      );
    });
    it("Should not finalized if base fee is less than zero", async () => {
      const baseFee = 0;
      const qMin = (1 * Math.pow(10, 6)).toString();
      const pMin = (0.01 * Math.pow(10, 18)).toString();
      const exposureLimitPrimary = (0.25 * Math.pow(10, 18)).toString();
      const exposureLimitComplement = (0.25 * Math.pow(10, 18)).toString();
      const leveragePrimary = "999996478162223000";
      const leverageComplement = "1000003521850180000";
      const MAX = "10000000000000000000000";
      await expectRevert.unspecified(
        pool.finalize(
          "100000000000000000000",
          leveragePrimary,
          "1000000000000000000",
          leverageComplement,
          exposureLimitPrimary,
          exposureLimitComplement,
          pMin,
          qMin,
          owner
        ),
        "VolmexPool: baseFee should be larger than 0"
      );
    });

    it("Should not swap if protocol is settled", async () => {
      await protocol.settle(150);

      await expectRevert(
        pool.swapExactAmountIn(
          volatility.address,
          "3000000000000000000",
          inverseVolatility.address,
          "1000000000000000000",
          owner,
          false
        ),
        "VolmexPool: Protocol is settled"
      );
    });

    it("Should revert when finalize call", async () => {
      const qMin = (1 * Math.pow(10, 6)).toString();
      const pMin = (0.01 * Math.pow(10, 18)).toString();
      const exposureLimitPrimary = (0.25 * Math.pow(10, 18)).toString();
      const exposureLimitComplement = (0.25 * Math.pow(10, 18)).toString();
      const leveragePrimary = "999996478162223000";
      const leverageComplement = "1000003521850180000";

      await expectRevert(
        pool.finalize(
          "1000000000000000000",
          leveragePrimary,
          "1000000000000000000",
          leverageComplement,
          exposureLimitPrimary,
          exposureLimitComplement,
          pMin,
          qMin,
          owner
        ),
        "VolmexPool: Pool is finalized"
      );
    });

    it("Should revert join pool", async () => {
      await (await volatility.approve(pool.address, "20000000000000000000")).wait();
      await (await inverseVolatility.approve(pool.address, "20000000000000000000")).wait();
      await expectRevert(
        pool.joinPool("0", ["20000000000000000000", "20000000000000000000"], owner),
        "VolmexPool: Invalid math approximation"
      );

      await expectRevert(
        pool.joinPool(
          "3000000000000000000000",
          ["2000000000000000000", "2000000000000000000"],
          owner
        ),
        "VolmexPool: Amount in limit exploit"
      );
    });

    it("Should revert if pool is not finalized", async () => {
      const baseFee = (0.02 * Math.pow(10, 18)).toString();
      const maxFee = (0.4 * Math.pow(10, 18)).toString();
      const feeAmpPrimary = 10;
      const feeAmpComplement = 10;
      pool = await upgrades.deployProxy(poolFactory, [
        repricer.address,
        protocol.address,
        "0",
        baseFee,
        maxFee,
        feeAmpPrimary,
        feeAmpComplement,
        owner
      ]);
      await pool.deployed();
      await (await volatility.approve(pool.address, "20000000000000000000")).wait();
      await (await inverseVolatility.approve(pool.address, "20000000000000000000")).wait();
      await expectRevert(
        pool.joinPool(
          "3000000000000000000000",
          ["20000000000000000000", "20000000000000000000"],
          owner
        ),
        "VolmexPool: Pool is not finalized"
      );
    });

    it("Should revert exit pool", async () => {
      await expectRevert(
        pool.exitPool("0", ["1000000000000000000", "1000000000000000000"], owner),
        "VolmexPool: Invalid math approximation"
      );

      await expectRevert(
        pool.exitPool(
          "250000000000000000000",
          ["2000000000000000000", "2000000000000000000"],
          owner
        ),
        "VolmexPool: Amount out limit exploit"
      );
    });

    it("Should revert swap", async () => {
      await (await volatility.approve(pool.address, "3000000000000000000")).wait();
      await expectRevert(
        pool.swapExactAmountIn(
          volatility.address,
          "3000000000000000000",
          volatility.address,
          "1000000000000000000",
          owner,
          false
        ),
        "VolmexPool: Passed same token addresses"
      );

      await (await volatility.approve(pool.address, "3000000000000000000")).wait();
      await expectRevert(
        pool.swapExactAmountIn(
          volatility.address,
          "10000",
          inverseVolatility.address,
          "1000000000000000000",
          owner,
          false
        ),
        "VolmexPool: Amount in quantity should be larger"
      );

      await (await volatility.approve(pool.address, "6599999999999998746")).wait();
      await expectRevert(
        pool.swapExactAmountIn(
          volatility.address,
          "65999999999999987460",
          inverseVolatility.address,
          "1000000000000000000",
          owner,
          false
        ),
        "VolmexPool: Amount in max ratio exploit"
      );
    });

    it("Should revert on limit out", async () => {
      await (await volatility.approve(pool.address, "20000000000000000000")).wait();
      await (await inverseVolatility.approve(pool.address, "20000000000000000000")).wait();
      const joinReceipt = await pool.joinPool(
        "3000000000000000000000",
        ["20000000000000000000", "20000000000000000000"],
        owner
      );
      await joinReceipt.wait();

      await (await volatility.approve(pool.address, "3000000000000000000")).wait();
      await expectRevert(
        pool.swapExactAmountIn(
          volatility.address,
          "3000000000000000000",
          inverseVolatility.address,
          "3000000000000000000",
          owner,
          false
        ),
        "VolmexPool: Amount out limit exploit"
      );
    });
  });

  describe("Modifers", () => {
    it("Should revert on not controller", async () => {
      await expectRevert(
        pool
          .connect(accounts[1])
          .joinPool(
            "7000000000000000000000",
            ["30000000000000000000", "30000000000000000000"],
            await accounts[1].getAddress()
          ),
        "VolmexPool: Caller is not controller"
      );
    });
  });

  describe("Swap revert", () => {
    let bytes32: string;
    this.beforeEach(async () => {
      bytes32 = "0x6c00000000000000000000000000000000000000000000000000000000000000";
    });
    it("Exposure boundary", async () => {
      await (
        await volmexOracle.updateBatchVolatilityTokenPrice([0], ["125000000"], [bytes32])
      ).wait();
      const amountOut = await pool.getTokenAmountOut(volatility.address, "10000000000000000000");
      await (await volatility.approve(pool.address, "10000000000000000000")).wait();
      await expectRevert(
        pool.swapExactAmountIn(
          volatility.address,
          "10000000000000000000",
          inverseVolatility.address,
          amountOut[0].toString(),
          owner,
          false
        ),
        "VolmexPool: Exposure boundary"
      );
    });
  });

  describe("Pool token", () => {
    let setAmount: string;
    this.beforeEach(async () => {
      setAmount = "10000000000000000000";
    });

    it("Approve the assets", async () => {
      const beforeAllowance = await pool.allowance(owner, pool.address);
      await (await pool.approve(pool.address, setAmount)).wait();
      const afterAllowance = await pool.allowance(owner, pool.address);
      const changedBalance = afterAllowance.sub(beforeAllowance);
      expect(Number(changedBalance.toString())).to.equal(Number(setAmount));
    });

    it("Increase approval", async () => {
      const beforeAllowance = await pool.allowance(owner, pool.address);
      await (await pool.increaseApproval(pool.address, setAmount)).wait();
      const afterAllowance = await pool.allowance(owner, pool.address);
      const changedBalance = afterAllowance.sub(beforeAllowance);
      expect(Number(changedBalance.toString())).to.equal(Number(setAmount));
    });

    it("Decrease approval", async () => {
      await (await pool.approve(pool.address, setAmount)).wait();
      const beforeAllowance = await pool.allowance(owner, pool.address);
      await (await pool.decreaseApproval(pool.address, setAmount)).wait();
      await (await pool.decreaseApproval(pool.address, setAmount)).wait();
      const afterAllowance = await pool.allowance(owner, pool.address);
      const changedBalance = beforeAllowance.sub(afterAllowance);
      expect(Number(changedBalance.toString())).to.equal(Number(setAmount));
    });

    it("Transfer from", async () => {
      const beforeBalance = await pool.balanceOf(owner);
      await (await pool.approve(pool.address, setAmount)).wait();
      await (await pool.transferFrom(owner, await accounts[1].getAddress(), setAmount)).wait();
      const afterBalance = await pool.balanceOf(owner);
      const changedBalance = beforeBalance.sub(afterBalance);
      expect(Number(changedBalance.toString())).to.equal(Number(setAmount));

      await expectRevert(
        pool
          .connect(accounts[2])
          .transferFrom(await accounts[3].getAddress(), await accounts[4].getAddress(), setAmount),
        "TOKEN_BAD_CALLER"
      );

      await (await pool.connect(accounts[1]).approve(owner, setAmount)).wait();
      await (await pool.approve(pool.address, setAmount)).wait();
      await (
        await pool.transferFrom(
          await accounts[1].getAddress(),
          await accounts[2].getAddress(),
          setAmount
        )
      ).wait();
    });

    it("Transfer", async () => {
      const beforeBalance = await pool.balanceOf(owner);
      await (await pool.transfer(await accounts[1].getAddress(), setAmount)).wait();
      const afterBalance = await pool.balanceOf(owner);
      const changedBalance = beforeBalance.sub(afterBalance);
      expect(Number(changedBalance.toString())).to.equal(Number(setAmount));

      await expectRevert(
        pool.connect(accounts[2]).transfer(await accounts[1].getAddress(), setAmount),
        "INSUFFICIENT_BAL"
      );
    });

    it("Name and symbol", async () => {
      await pool.name();
      await pool.symbol();
      await pool.decimals();
    });
  });
});

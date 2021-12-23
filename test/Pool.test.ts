const { expect } = require('chai');
const { ethers, upgrades } = require('hardhat');
import { Signer } from 'ethers';
const { expectRevert, time } = require("@openzeppelin/test-helpers");

describe('VolmexPool', function () {
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
  let controllerFactory:  any;
  let controller: any;

  this.beforeAll(async function () {
    accounts = await ethers.getSigners();

    repricerFactory = await ethers.getContractFactory('VolmexRepricer');

    volmexOracleFactory = await ethers.getContractFactory('VolmexOracle');

    poolFactory = await ethers.getContractFactory('VolmexPool');

    collateralFactory = await ethers.getContractFactory('TestCollateralToken');

    volatilityFactory = await ethers.getContractFactory('VolmexPositionToken');

    protocolFactory = await ethers.getContractFactory('VolmexProtocol');

    controllerFactory = await ethers.getContractFactory('VolmexController');
  });

  this.beforeEach(async function () {
    collateral = await collateralFactory.deploy();
    await collateral.deployed();

    volatility = await volatilityFactory.deploy();
    await volatility.deployed();
    let volreceipt = await volatility.initialize('ETH Volatility Index', 'ETHV');
    await volreceipt.wait();

    inverseVolatility = await volatilityFactory.deploy();
    await inverseVolatility.deployed();
    volreceipt = await inverseVolatility.initialize('Inverse ETH Volatility Index', 'iETHV');
    await volreceipt.wait();

    protocol = await upgrades.deployProxy(protocolFactory, [
      `${collateral.address}`,
      `${volatility.address}`,
      `${inverseVolatility.address}`,
      '25000000000000000000',
      '250',
    ]);
    await protocol.deployed();
    await (await protocol.updateFees('10', '30')).wait();

    const VOLMEX_PROTOCOL_ROLE =
      '0x33ba6006595f7ad5c59211bde33456cab351f47602fc04f644c8690bc73c4e16';

    volreceipt = await volatility.grantRole(VOLMEX_PROTOCOL_ROLE, `${protocol.address}`);
    await volreceipt.wait();

    volreceipt = await inverseVolatility.grantRole(VOLMEX_PROTOCOL_ROLE, `${protocol.address}`);
    await volreceipt.wait();

    volmexOracle = await upgrades.deployProxy(volmexOracleFactory, [protocol.address]);
    await volmexOracle.deployed();

    repricer = await upgrades.deployProxy(repricerFactory, [
      volmexOracle.address
    ]);
    await repricer.deployed();

    const baseFee = (0.02 * Math.pow(10, 18)).toString();
    const maxFee = (0.4 * Math.pow(10, 18)).toString();
    const feeAmpPrimary = 10;
    const feeAmpComplement = 10;

    owner = await accounts[0].getAddress();
    pool = await upgrades.deployProxy(poolFactory, [
      repricer.address,
      protocol.address,
      '0',
      baseFee,
      maxFee,
      feeAmpPrimary,
      feeAmpComplement
    ]);
    await pool.deployed();

    const qMin = (1 * Math.pow(10, 6)).toString();
    const pMin = (0.01 * Math.pow(10, 18)).toString();
    const exposureLimitPrimary = (0.25 * Math.pow(10, 18)).toString();
    const exposureLimitComplement = (0.25 * Math.pow(10, 18)).toString();
    const leveragePrimary = '999996478162223000';
    const leverageComplement = '1000003521850180000';
    const MAX = '10000000000000000000000';

    await (await collateral.mint(owner, MAX)).wait();
    await (await collateral.approve(protocol.address, MAX)).wait();
    await (await protocol.collateralize(MAX)).wait();

    // Test non-controller finalise
    // await expectRevert(
    //   pool.finalize(
    //     '1000000000000000000',
    //     leveragePrimary,
    //     '1000000000000000000',
    //     leverageComplement,
    //     exposureLimitPrimary,
    //     exposureLimitComplement,
    //     pMin,
    //     qMin
    //   ),
    //   'NOT_SET_FEE_PARAMS'
    // );

    // // Test the finalize modifier
    // await expectRevert(
    //   pool.joinPool(
    //     '3000000000000000000000',
    //     ['20000000000000000000','20000000000000000000']
    //   ),
    //   'NOT_FINALIZED'
    // );

    // // Test non-controller finalise
    // await expectRevert(
    //   pool.connect(accounts[1]).finalize(
    //     '1000000000000000000',
    //     leveragePrimary,
    //     '1000000000000000000',
    //     leverageComplement,
    //     exposureLimitPrimary,
    //     exposureLimitComplement,
    //     pMin,
    //     qMin
    //   ),
    //   'NOT_CONTROLLER'
    // );

    // // Test tokens balance
    // await expectRevert(
    //   pool.finalize(
    //     '1000000000000000000',
    //     leveragePrimary,
    //     '100000000000000000',
    //     leverageComplement,
    //     exposureLimitPrimary,
    //     exposureLimitComplement,
    //     pMin,
    //     qMin
    //   ),
    //   'NOT_SYMMETRIC'
    // );

    // // Test the bind require checks
    // await expectRevert(
    //   pool.finalize(
    //     '100000',
    //     leveragePrimary,
    //     '100000',
    //     leverageComplement,
    //     exposureLimitPrimary,
    //     exposureLimitComplement,
    //     pMin,
    //     qMin
    //   ),
    //   'MIN_BALANCE'
    // );

    // // Test token leverage
    // await expectRevert(
    //   pool.finalize(
    //     '1000000000000000000',
    //     '0',
    //     '1000000000000000000',
    //     '0',
    //     exposureLimitPrimary,
    //     exposureLimitComplement,
    //     pMin,
    //     qMin
    //   ),
    //   'ZERO_LEVERAGE'
    // );

    controller = await upgrades.deployProxy(controllerFactory, [
      collateral.address,
      pool.address,
      protocol.address,
      volmexOracle.address

    ]);
    await controller.deployed();

    const setController = await pool.setController(controller.address);
    await setController.wait();

    await (await volatility.approve(controller.address, "1000000000000000000")).wait();
    await (await inverseVolatility.approve(controller.address, "1000000000000000000")).wait();

    const finalizeReceipt = await pool.finalize(
      '1000000000000000000',
      leveragePrimary,
      '1000000000000000000',
      leverageComplement,
      exposureLimitPrimary,
      exposureLimitComplement,
      pMin,
      qMin
    );
    await finalizeReceipt.wait();
  });

  it('should deploy pool', async () => {
    const poolreceipt = await pool.deployed();
    expect(poolreceipt.confirmations).not.equal(0);
  });

  it("Should check the swap amount", async () => {
    await (await volatility.approve(controller.address, "38960000000000000000")).wait();
    await (await inverseVolatility.approve(controller.address, "38960000000000000000")).wait();

    const add = await controller.addLiquidity(
      '7000000000000000000000',
      ['38960000000000000000','38960000000000000000'],
      '0'
    );
    await add.wait();

    await (await volatility.approve(controller.address, '6000000000000000000')).wait();

    let amountOut = await pool.getTokenAmountOut(
      volatility.address,
      '6000000000000000000',
      inverseVolatility.address
    );

    let swap = await controller.swap(
      '0',
      volatility.address,
      '6000000000000000000',
      inverseVolatility.address,
      amountOut[0].toString()
    );
    await swap.wait();
  });

  it ("Should update reprice", async () => {
    await (await volatility.approve(controller.address, "38960000000000000000")).wait();
    await (await inverseVolatility.approve(controller.address, "38960000000000000000")).wait();

    const test = await controller.addLiquidity(
      '7000000000000000000000',
      ['38960000000000000000','38960000000000000000'],
      '0'
    );
    await test.wait();

    const latest = await time.latestBlock();
    await (await inverseVolatility.approve(controller.address, '3000000000000000000')).wait();

    let amountOut = await pool.getTokenAmountOut(
      inverseVolatility.address,      
      '3000000000000000000',
      volatility.address,
    );

    let swap = await controller.swap(
      '0',
      inverseVolatility.address,
      '3000000000000000000',
      volatility.address,
      '1000000000000000000'
    );
    let swapreceipt = await swap.wait();

    amountOut = await pool.getTokenAmountOut(
      inverseVolatility.address,      
      '3000000000000000000',
      volatility.address,
    );

    await time.advanceBlockTo(parseInt(latest) + 5);
    const current = await time.latestBlock();

    amountOut = await pool.getTokenAmountOut(
      inverseVolatility.address,      
      '3000000000000000000',
      volatility.address,
    );

    await (await inverseVolatility.approve(controller.address, '3000000000000000000')).wait();

    const swap2 = await controller.swap(
      '0',
      inverseVolatility.address,
      '3000000000000000000',
      volatility.address,
      '1000000000000000000'
    );
    await swap.wait();
  });

  it ("Should test", async () => {
    await (await volatility.approve(controller.address, "38960000000000000000")).wait();
    await (await inverseVolatility.approve(controller.address, "38960000000000000000")).wait();

    const test = await controller.addLiquidity(
      '7000000000000000000000',
      ['38960000000000000000','38960000000000000000'],
      '0'
    );
    await test.wait();
    let amountOut = await pool.getTokenAmountOut(
      inverseVolatility.address,
      '20000000000000000000',
      volatility.address
    );
    await (await volatility.approve(controller.address, '3000000000000000000')).wait();

    const swap = await controller.swap(
      '0',
      inverseVolatility.address,
      '3000000000000000000',
      volatility.address,
      '1000000000000000000'
    );
    const swapreceipt = await swap.wait();

    amountOut = await pool.getTokenAmountOut(
      inverseVolatility.address,
      '20000000000000000000',
      volatility.address
    );

    await (await volatility.approve(controller.address, '3000000000000000000')).wait();

    const swap2 = await controller.swap(
      '0',
      inverseVolatility.address,
      '3000000000000000000',
      volatility.address,
      '1000000000000000000'
    );
    await swap.wait();
  });

  it('Should show logs', async () => {
    await (await volatility.approve(controller.address, "20000000000000000000")).wait();
    await (await inverseVolatility.approve(controller.address, "20000000000000000000")).wait();

    const test = await controller.addLiquidity(
      '3000000000000000000000',
      ['20000000000000000000','20000000000000000000'],
      '0'
    );
    await test.wait();
  })

  it('Should get out amount', async () => {
    await (await volatility.approve(controller.address, "20000000000000000000")).wait();
    await (await inverseVolatility.approve(controller.address, "20000000000000000000")).wait();
    const joinReceipt = await controller.addLiquidity(
      '3000000000000000000000',
      ['20000000000000000000','20000000000000000000'],
      '0'
    )

    await joinReceipt.wait();

    const amount = await pool.getTokenAmountOut(
      volatility.address,
      '10000000000000000000',
      inverseVolatility.address
    );
  });

  it('should swap the assets', async () => {
    await (await volatility.approve(controller.address, "20000000000000000000")).wait();
    await (await inverseVolatility.approve(controller.address, "20000000000000000000")).wait();
    const joinReceipt = await controller.addLiquidity(
      '3000000000000000000000',
      ['20000000000000000000','20000000000000000000'],
      '0'
    );
    await joinReceipt.wait();
    await (await volatility.approve(controller.address, '3000000000000000000')).wait();

    const swap = await controller.swap(
      '0',
      volatility.address,
      '3000000000000000000',
      inverseVolatility.address,
      '1000000000000000000'
    );
    const swapreceipt = await swap.wait();
    expect(swapreceipt.confirmations).equal(1);
  });

  it('Should user eit liquidity from pool', async () => {
    await (await volatility.approve(controller.address, "20000000000000000000")).wait();
    await (await inverseVolatility.approve(controller.address, "20000000000000000000")).wait();
    const joinReceipt = await controller.addLiquidity(
      '3000000000000000000000',
      ['20000000000000000000','20000000000000000000'],
      '0'
    );
    await joinReceipt.wait();

    const eitReceipt = await controller.removeLiquidity(
      '1000000000000000000000',
      ['1000000000000000000','1000000000000000000'],
      '0'
    );
    await eitReceipt.wait();
  });

  it('Should volatility tokens', async () => {
    const receipt = await pool.getTokens();

    expect(await receipt[0]).to.equal(await protocol.volatilityToken());
    expect(await receipt[1]).to.equal(await protocol.inverseVolatilityToken());
  });

  it('Should return the token leverage', async () =>{
    let receipt = await pool.getLeverage(await protocol.volatilityToken());
    expect(await receipt).not.equal(0);

    receipt = await pool.getLeverage(await protocol.inverseVolatilityToken());
    expect(await receipt).not.equal(0);
  });

  it('Should return the reserve of token', async () => {
    let receipt = await pool.getBalance(await protocol.volatilityToken());
    expect(await receipt).not.equal(0);

    receipt = await pool.getBalance(await protocol.inverseVolatilityToken());
    expect(await receipt).not.equal(0);
  });

  it('Should pause/unpause the tokens', async () => {
    let receipt = await pool.pause();
    expect(receipt.confirmations).equal(1);

    receipt = await pool.unpause();
    expect(receipt.confirmations).equal(1);
  });

  it('Should check the pool is finalized', async () => {
    let receipt = await pool.isFinalized();
    expect(receipt).equal(true);
  });

  it('Should not swap if protocol is settled', async () => {
    await protocol.settle(150);

    await expectRevert(
      controller.swap(
        '0',
        volatility.address,
        '3000000000000000000',
        inverseVolatility.address,
        '1000000000000000000'
      ),
      'VolmexPool: Protocol is settled'
    );
  });

  it('Should revert on non controller', async () => {
    const [ other ] = accounts;

    await expectRevert(
      pool.setController('0x0000000000000000000000000000000000000000'),
      'VolmexPool: Deployer can not be zero address'
    );
  });

  it('Should revert when finalize call', async () => {
    const qMin = (1 * Math.pow(10, 6)).toString();
    const pMin = (0.01 * Math.pow(10, 18)).toString();
    const exposureLimitPrimary = (0.25 * Math.pow(10, 18)).toString();
    const exposureLimitComplement = (0.25 * Math.pow(10, 18)).toString();
    const leveragePrimary = '999996478162223000';
    const leverageComplement = '1000003521850180000';

    await expectRevert(
      pool.finalize(
        '1000000000000000000',
        leveragePrimary,
        '1000000000000000000',
        leverageComplement,
        exposureLimitPrimary,
        exposureLimitComplement,
        pMin,
        qMin
      ),
      'VolmexPool: Pool is finalized'
    );
  });

  it('Should revert join pool', async () => {
    await (await volatility.approve(controller.address, "20000000000000000000")).wait();
    await (await inverseVolatility.approve(controller.address, "20000000000000000000")).wait();
    await expectRevert(
      controller.addLiquidity(
        '0',
        ['20000000000000000000','20000000000000000000'],
        '0'
      ),
      'VolmexPool: Invalid math approximation'
    );

    await expectRevert(
      controller.addLiquidity(
        '3000000000000000000000',
        ['2000000000000000000','2000000000000000000'],
        '0'
      ),
      'VolmexPool: Amount in limit exploit'
    );
  });

  it('Should revert exit pool', async () => {
    await expectRevert(
      controller.removeLiquidity(
        '0',
        ['1000000000000000000','1000000000000000000'],
        '0'
      ),
      'VolmexPool: Invalid math approximation'
    );

    await expectRevert(
      controller.removeLiquidity(
        '250000000000000000000',
        ['2000000000000000000','2000000000000000000'],
        '0'
      ),
      'VolmexPool: Amount out limit exploit'
    );
  });

  it('Should revert swap', async () => {
    await (await volatility.approve(controller.address, '3000000000000000000')).wait();
    await expectRevert(
      controller.swap(
        '0',
        volatility.address,
        '3000000000000000000',
        volatility.address,
        '1000000000000000000'
      ),
      'VolmexPool: Passed same token addresses'
    );

    await (await volatility.approve(controller.address, '3000000000000000000')).wait();
    await expectRevert(
      controller.swap(
        '0',
        volatility.address,
        '100000',
        inverseVolatility.address,
        '1000000000000000000'
      ),
      'VolmexPool: Amount in quantity should be larger'
    );

    await (await volatility.approve(controller.address, '6599999999999998746')).wait();
    await expectRevert(
      controller.swap(
        '0',
        volatility.address,
        '6599999999999998746',
        inverseVolatility.address,
        '1000000000000000000'
      ),
      'VolmexPool: Amount in max ratio exploit'
    );
  });

  it('Should revert on limit out', async () => {
    await (await volatility.approve(controller.address, "20000000000000000000")).wait();
    await (await inverseVolatility.approve(controller.address, "20000000000000000000")).wait();
    const joinReceipt = await controller.addLiquidity(
      '3000000000000000000000',
      ['20000000000000000000','20000000000000000000'],
      '0'
    );
    await joinReceipt.wait();

    await (await volatility.approve(controller.address, '3000000000000000000')).wait();
    await expectRevert(
      controller.swap(
        '0',
        volatility.address,
        '3000000000000000000',
        inverseVolatility.address,
        '3000000000000000000'
      ),
      'VolmexPool: Amount out limit exploit'
    );
  });

  it('Should revert require boundary exposure', async () => {
    await (await volatility.approve(controller.address, "16000000000000000000")).wait();
    await (await inverseVolatility.approve(controller.address, "16000000000000000000")).wait();
    const joinReceipt = await controller.addLiquidity(
      '4000000000000000000000',
      ['16000000000000000000','16000000000000000000'],
      '0'
    );
    await joinReceipt.wait();

    await (await volatility.approve(controller.address, '8000000000000000000')).wait();
    await expectRevert(
      controller.swap(
        '0',
        volatility.address,
        '8000000000000000000',
        inverseVolatility.address,
        '1000000000000000000'
      ),
      'VolmexPool: Exposure boundary'
    );
  });

  it('should deploy controller', async () => {
    const controllerReceipt = await controller.deployed();
    expect(controllerReceipt.confirmations).not.equal(0);
  });

  it('Should swap the collateral to volatility', async () => {
    await (await volatility.approve(controller.address, "16000000000000000000")).wait();
    await (await inverseVolatility.approve(controller.address, "16000000000000000000")).wait();
    const joinReceipt = await controller.addLiquidity(
      '4000000000000000000000',
      ['16000000000000000000','16000000000000000000'],
      '0'
    );
    await joinReceipt.wait();

    await (await collateral.approve(controller.address, '10000000000000000000000')).wait();

    const collateralSymbol = await collateral.symbol();
    const swapReceipt = await controller.swapCollateralToVolatility(
      '250000000000000000000',
      true,
      '0',
      collateralSymbol
    );
    const {events} = await swapReceipt.wait();
    let data;
    events.forEach((log: any) => {
      if (log['event'] == 'AssetSwaped') {
        data = log['data'];
      }
    })
    const logData = ethers.utils.defaultAbiCoder.decode(
      [ 'uint256' , 'uint256' ],
      data
    );
  });

  it('Should swap volatility to collateral', async () => {
    await (await volatility.approve(controller.address, "16000000000000000000")).wait();
    await (await inverseVolatility.approve(controller.address, "16000000000000000000")).wait();
    const joinReceipt = await controller.addLiquidity(
      '4000000000000000000000',
      ['16000000000000000000','16000000000000000000'],
      '0'
    );
    await joinReceipt.wait();

    await (await inverseVolatility.approve(controller.address, '10000000000000000000')).wait();
    await (await volatility.approve(controller.address, '10000000000000000000')).wait();

    const collateralBefore = Number(await collateral.balanceOf(owner));

    const swapReceipt = await controller.swapVolatilityToCollateral(
      ['2000000000000000000','2000000000000000000'], ['0','1'], await pool.address
    );
    const {events} = await swapReceipt.wait();
    const collateralAfter = Number(await collateral.balanceOf(owner));

    let data;
    events.forEach((log: any) => {
      if (log['event'] == 'AssetSwaped') {
        data = log['data'];
      }
    })
    const logData = ethers.utils.defaultAbiCoder.decode(
      [ 'uint256' , 'uint256' ],
      data
    );

    expect(Number(collateralAfter - collateralBefore)).be.closeTo(Number(logData[1].toString()), 3600000);
  });
});

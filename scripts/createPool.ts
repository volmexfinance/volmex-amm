import { ethers, upgrades, run } from "hardhat";

const Protocols = [
  "0xFc016C2109B88413E7cbeBf81b000d8E91c53bD0", // ETH DAI
  "0x341B0Be0cc91d05937d7AcA43e6b55dBb37aa62a", // ETH USDC
  "0x322209955f9A62519961ABac71CDbA6CB1708E24", // BTC DAI
  "0x0553205605A6611dA5c595C46E47A5BBC9B19e14", // BTC USDC
];

const Volatility = [
  "0x621C37853FF4bFF3089b93f5f0B47fAea16C0767", // ETHV
  "0xf91BA2E8047b8A2Cbf15c188bC1638a187C9a741",
  "0x654CAe450283dC5C64F73B096eD36c5Bf38f68F3", //BTCV
  "0x188B15A084b4107797c8Fc4E0AC33eDc9AE0D895",
];

const StableCoins = [
  "0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063", // DAI
  "0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174", // USDC
];

const createPool = async () => {
  const accounts = await ethers.getSigners();
  console.log("Deployer: ", await accounts[0].getAddress());
  console.log("balance: ", await accounts[0].getBalance());

  const Pool = await ethers.getContractFactory("VolmexPool");
  const VolmexRepricer = await ethers.getContractFactory("VolmexRepricer");
  const VolmexOracle = await ethers.getContractFactory("VolmexOracle");
  const ControllerFactory = await ethers.getContractFactory("VolmexController");
  const VolmexPoolView = await ethers.getContractFactory("VolmexPoolView");
  let governor = await accounts[0].getAddress();
  if (process.env.GOVERNOR) {
    governor = `${process.env.GOVERNOR}`;
  }

  const BigNumber = require("bignumber.js");
  const bn = (num: number) => new BigNumber(num);

  const baseFee = (0.02 * Math.pow(10, 18)).toString();
  const maxFee = (0.4 * Math.pow(10, 18)).toString();
  const feeAmpPrimary = 10;
  const feeAmpComplement = 10;
  const qMin = (1 * Math.pow(10, 6)).toString();
  const pMin = (0.01 * Math.pow(10, 18)).toString();
  const exposureLimitPrimary = (0.25 * Math.pow(10, 18)).toString();
  const exposureLimitComplement = (0.25 * Math.pow(10, 18)).toString();
  const leveragePrimary = "999996478162223000";
  const leverageComplement = "1000003521850180000";

  console.log("Deploying Oracle...");

  const oracle = await VolmexOracle.attach("0x9AD8D5fec1B2dFF3f35F91eb5F638C8Bac6E5E38");
  // await upgrades.deployProxy(VolmexOracle, ["0x99f4588F53DdC0B0197D82bfeFc620dE0c485eD0"]);
  // await oracle.deployed();
  console.log("VolmexOracle deployed ", oracle.address);

  console.log("Deploying Repricer...");
  const repricer = await VolmexRepricer.attach("0x5d0D8CC099ADF1D3ada5aD2066A03d57aeBB4a82");
  // await upgrades.deployProxy(VolmexRepricer, [oracle.address, governor]);
  // await repricer.deployed();
  console.log("VolmexRepricer deployed ", repricer.address);

  console.log("Creating pool... ");
  const poolETH = await upgrades.deployProxy(Pool, [
    repricer.address,
    Protocols[0],
    "0",
    baseFee,
    maxFee,
    feeAmpPrimary,
    feeAmpComplement,
    governor,
  ]);
  await poolETH.deployed();
  console.log("ETH Pool deployed ", poolETH.address);

  const poolBTC = await upgrades.deployProxy(Pool, [
    repricer.address,
    Protocols[2],
    "1",
    baseFee,
    maxFee,
    feeAmpPrimary,
    feeAmpComplement,
    governor,
  ]);
  await poolBTC.deployed();
  console.log("BTC Pool deployed ", poolBTC.address);

  const ethv = await ethers.getContractAt("IERC20Modified", Volatility[0]);
  const iethv = await ethers.getContractAt("IERC20Modified", Volatility[1]);

  const btcv = await ethers.getContractAt("IERC20Modified", Volatility[2]);
  const ibtcv = await ethers.getContractAt("IERC20Modified", Volatility[3]);

  console.log("Deploying controller ...");
  const controller = await upgrades.deployProxy(ControllerFactory, [
    StableCoins,
    [poolETH.address, poolBTC.address],
    Protocols,
    governor,
  ]);
  await controller.deployed();
  console.log("VolmexController deployed :", controller.address);

  console.log("Setting pools controller ...");
  await (await poolETH.setController(controller.address)).wait();
  await (await poolBTC.setController(controller.address)).wait();
  console.log("Set pools controller");

  const joinAmount = "100000000000000000";

  console.log("Approve volatility to pool ETH");
  await ethv.approve(controller.address, joinAmount);
  await iethv.approve(controller.address, joinAmount);

  console.log("Approve volatility to pool BTC");
  await btcv.approve(controller.address, joinAmount);
  await ibtcv.approve(controller.address, joinAmount);

  console.log("Finalize Pools");
  await (
    await controller.finalizePool(
      0,
      joinAmount,
      leveragePrimary,
      joinAmount,
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
      joinAmount,
      leveragePrimary,
      joinAmount,
      leverageComplement,
      exposureLimitPrimary,
      exposureLimitComplement,
      pMin,
      qMin
    )
  ).wait();
  console.log("Pools finalized!");

  console.log("Deploying Pool view ...");
  const poolView = await upgrades.deployProxy(VolmexPoolView, [controller.address]);
  await poolView.deployed();
  console.log("VolmexPoolView deployed", poolView.address);

  console.log("\nDeployment History");
  console.log("VolmexPool ETH: ", poolETH.address);
  console.log("VolmexPool BTC: ", poolBTC.address);
  console.log("VolmexRepricer: ", repricer.address);
  console.log("VolmexOracle: ", oracle.address);
  console.log("Controller: ", controller.address);
  console.log("VolmexAMMView: ", poolView.address);

  const proxyAdmin = await upgrades.admin.getInstance();

  try {
    await run("verify:verify", {
      address: await proxyAdmin.getProxyImplementation(poolETH.address),
    });
  } catch (error: any) {}
  try {
    await run("verify:verify", {
      address: await proxyAdmin.getProxyImplementation(repricer.address),
    });
  } catch (error: any) {}
  try {
    await run("verify:verify", {
      address: await proxyAdmin.getProxyImplementation(oracle.address),
    });
  } catch (error: any) {}
  try {
    await run("verify:verify", {
      address: await proxyAdmin.getProxyImplementation(controller.address),
    });
  } catch (error: any) {}
  try {
    await run("verify:verify", {
      address: await proxyAdmin.getProxyImplementation(poolView.address),
    });
  } catch (error: any) {}
  try {
    await run("verify:verify", {
      address: await proxyAdmin.getProxyImplementation(poolBTC.address),
    });
  } catch (error: any) {}
};

createPool()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("Error: ", error);
    process.exit(1);
  });

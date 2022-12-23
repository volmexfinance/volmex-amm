import { ethers, upgrades, run } from "hardhat";

const Protocols = [
  "0x88B6E66543bF5E533CDd347E1Dd222DB4307e5dC", //  DAI
  "0xE2334071820cba1320f464844f9e3BeB31254813", //  USDC
];

const Volatility = [
  "0x098ec8a760fF9B12c84A9f6a17015A009916c841", // normal
  "0x220563b3F3Ab8A8E32d8BDac9B3880D4ccF85997", // inverse
];

const StableCoins = [
  "0xeabf1b4f19439af69302d6701a00e3c34d0ad20b", // DAI
  "0xaFD38467Ef8b9048Ddb853221dE79f993a103f21", // USDC
];

const createPool = async () => {
  const accounts = await ethers.getSigners();
  console.log("Deployer: ", await accounts[0].getAddress());
  console.log("balance: ", await accounts[0].getBalance());

  const Pool = await ethers.getContractFactory("VolmexPool");
  const VolmexRepricer = await ethers.getContractFactory("VolmexRepricer");
  const VolmexOracle = await ethers.getContractFactory("VolmexOracle");
  const ControllerFactory = await ethers.getContractFactory("VolmexController");
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
  const exposureLimitPrimary = (0.4 * Math.pow(10, 18)).toString();
  const exposureLimitComplement = (0.4 * Math.pow(10, 18)).toString();
  const leveragePrimary = "999996478162223000";
  const leverageComplement = "1000003521850180000";

  console.log("Deploying Oracle...");
  const oracle = VolmexOracle.attach(`${process.env.ORACLE}`);
  console.log("VolmexOracle deployed ", oracle.address);

  console.log("Deploying Repricer...");
  const repricer = VolmexRepricer.attach(`${process.env.REPRICER}`);
  console.log("VolmexRepricer deployed ", repricer.address);

  console.log("Creating pool... ");
  const pool = await upgrades.deployProxy(Pool, [
    repricer.address,
    Protocols[0],
    process.env.ORACLE_INDEX,
    baseFee,
    maxFee,
    feeAmpPrimary,
    feeAmpComplement,
    governor,
  ]);
  await pool.deployed();
  console.log("Pool deployed ", pool.address);

  const volatility = await ethers.getContractAt("IERC20Modified", Volatility[0]);
  const inverseVolatility = await ethers.getContractAt("IERC20Modified", Volatility[1]);

  console.log("Deploying controller ...");
  const controller = ControllerFactory.attach(`${process.env.CONTROLLER}`);
  console.log("VolmexController deployed :", controller.address);
  console.log("Add pool to controller ...");
  await (await controller.addPool(pool.address)).wait();
  console.log("Added pool to controller");
  console.log("Add protocol to controller ...");
  await (await controller.addProtocol(3, 0, Protocols[0])).wait();
  await (await controller.addProtocol(3, 1, Protocols[1])).wait();
  console.log("Added protocol to controller");

  console.log("Setting pools controller ...");
  await (await pool.setController(controller.address)).wait();
  console.log("Set pools controller");

  const joinAmount = "100000000000000000";

  console.log("Approve volatility to pool ETH");
  await volatility.approve(controller.address, joinAmount);
  await inverseVolatility.approve(controller.address, joinAmount);

  console.log("Finalize Pools");
  await (
    await controller.finalizePool(
      3,
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

  console.log("\nDeployment History\n");
  console.log("VolmexPool: ", pool.address);

  const proxyAdmin = await upgrades.admin.getInstance();

  try {
    await run("verify:verify", {
      address: await proxyAdmin.getProxyImplementation(pool.address),
    });
  } catch (error: any) {}
};

createPool()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("Error: ", error);
    process.exit(1);
  });

import { ethers, upgrades, run } from "hardhat";

const createPool = async () => {
  const [owner] = await ethers.getSigners();
  console.log("Balance: ", (await owner.getBalance()).toString());
  const contract = await ethers.getContractFactory(`${process.env.CONTRACT_NAME}`);

  console.log("Upgrading contract ...");
  const instance = await upgrades.upgradeProxy(`${process.env.CONTRACT_ADDRESS}`, contract);
  await instance.deployed();

  const proxyAdmin = await upgrades.admin.getInstance();
  const implementation = await proxyAdmin.getProxyImplementation(instance.address)
  console.log("Upgraded, implementation: ", implementation)

  await run("verify:verify", {
    address: implementation,
  });
};

createPool()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("Error: ", error);
    process.exit(1);
  });

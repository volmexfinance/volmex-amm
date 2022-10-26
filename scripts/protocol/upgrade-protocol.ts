import { ethers, upgrades, run } from "hardhat";

const upgrade = async () => {
  const proxyAddress = `${process.env.PROXY_ADDRESS}`;

  const VolmexProtocolV2Factory = await ethers.getContractFactory(
    `${process.env.VOLMEX_PROTOCOL}`
  );
  const proxyAdmin = await upgrades.admin.getInstance();
  console.log("proxyAdmin", proxyAdmin);
  const volmexProtocolInstance = await upgrades.upgradeProxy(
    proxyAddress,
    VolmexProtocolV2Factory
  );

  console.log("proxyAdmin", proxyAdmin);

  await (
    await volmexProtocolInstance.setV2Protocol(
      process.env.VOLMEX_PROTOCOL_V2,
      true,
      process.env.VOLATILITY_CAP_RATIO
    )
  ).wait();

  // @ts-ignore
  const protocolImplementation = await proxyAdmin.getProxyImplementation(
    volmexProtocolInstance.address
  );

  await run("verify:verify", {
    address: protocolImplementation,
  });

  console.log("Volmex Protocol implementation upgraded");
};

upgrade()
  .then(() => process.exit(0))
  .catch((error) => {
    console.log("Error: ", error);
    process.exit(1);
  });

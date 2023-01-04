import { ethers, upgrades, run, network } from "hardhat";
import { Contract, ContractReceipt, Event } from "ethers";
import { Result } from "@ethersproject/abi";
const LZ_ENDPOINTS = require("../../constants/layerzeroEndpoints.json")

const filterEvents = (blockEvents: ContractReceipt, name: String): Array<Event> => {
  return blockEvents.events?.filter((event) => event.event === name) || [];
};

export const decodeEvents = <T extends Contract>(
  token: T,
  events: Array<Event>
): Array<Result> => {
  const decodedEvents = [];
  for (const event of events) {
    const getEventInterface = token.interface.getEvent(event.event || "");
    decodedEvents.push(
      token.interface.decodeEventLog(getEventInterface, event.data, event.topics)
    );
  }
  return decodedEvents;
};

const deploy = async () => {
  const endpointAddr = LZ_ENDPOINTS[network.name];
  
  console.log(`[${network.name}] Endpoint address: ${endpointAddr}`);

  const VolmexPositionTokenFactory = await ethers.getContractFactory(`${process.env.TOKEN_CONTRACT_NAME}`);

  const VolmexProtocolFactory = await ethers.getContractFactory(
    `${process.env.VOLMEX_PROTOCOL_CONTRACT}`
  );
  const VolmexIndexFactory = await ethers.getContractFactory(`${process.env.FACTORY_CONTRACT_NAME}`);
  const TestCollateralFactory = await ethers.getContractFactory("TestCollateralToken");

  let CollateralTokenAddress: string = `${process.env.COLLATERAL_TOKEN_ADDRESS}`;

  if (!process.env.COLLATERAL_TOKEN_ADDRESS) {
    const TestCollateralFactoryInstance = await TestCollateralFactory.deploy(
      process.env.COLLATERAL_TOKEN_SYMBOL,
      "1000000000000000000000",
      process.env.COLLATERAL_TOKEN_DECIMALS
    );

    CollateralTokenAddress = (await TestCollateralFactoryInstance.deployed()).address;

    console.log("Test Collateral Token deployed to: ", CollateralTokenAddress);
    try {
      await run("verify:verify", {
        address: CollateralTokenAddress,
        constructorArguments: [
          process.env.COLLATERAL_TOKEN_SYMBOL,
          "1000000000000000000000",
          process.env.COLLATERAL_TOKEN_DECIMALS
        ]
      });
    } catch (error: any) {}
  }

  let volmexIndexFactoryInstance, proxyAdmin;
  if (process.env.FACTORY_ADDRESS) {
    volmexIndexFactoryInstance = VolmexIndexFactory.attach(`${process.env.FACTORY_ADDRESS}`);
  } else {
    console.log("Deploying Layer1VolmexPositionToken implementation...");

    const volmexPositionTokenFactoryInstance = await VolmexPositionTokenFactory.deploy();
    await volmexPositionTokenFactoryInstance.deployed();
    console.log("Layer1VolmexPositionToken deployed...");

    try {
      await run("verify:verify", {
        address: volmexPositionTokenFactoryInstance.address,
      });
      console.log("Verification complete: Layer1VolmexPositionToken");
    } catch (error: any) {
      console.log("Error while verifying VolmexPositionTokenFactory");
      console.log(error);
    }

    console.log("Deploying VolmexIndexFactory...");

    volmexIndexFactoryInstance = await upgrades.deployProxy(VolmexIndexFactory, [
      volmexPositionTokenFactoryInstance.address,
    ]);
    await volmexIndexFactoryInstance.deployed();

    console.log("Index Factory proxy deployed to: ", volmexIndexFactoryInstance.address);

    proxyAdmin = await upgrades.admin.getInstance();
    console.log("Proxy Admin deployed to:", proxyAdmin.address);

    const factoryImplementation = await proxyAdmin.getProxyImplementation(
      volmexIndexFactoryInstance.address
    );

    console.log("Verifying VolmexIndexFactory on etherscan...");
    try {
      await run("verify:verify", {
        address: factoryImplementation,
      });
    } catch (error: any) {
      console.log("Error while verifying VolmexIndexFactory");
    }
  }

  let positionTokenCreatedEvent;
  let volatilityTokenAddress, inverseVolatilityTokenAddress;
  if (!process.env.VOLATILITY_TOKEN_ADDRESS) {
    let volatilityToken;
    if (!process.env.IS_LAYER_ZERO_TOKEN) {
      volatilityToken = await volmexIndexFactoryInstance.createVolatilityTokens(
        `${process.env.VOLATILITY_TOKEN_NAME}`,
        `${process.env.VOLATILITY_TOKEN_SYMBOL}`,
        `${process.env.INVERSE_VOLATILITY_TOKEN_NAME}`,
        `${process.env.INVERSE_VOLATILITY_TOKEN_SYMBOL}`,
      );
    } else {
      volatilityToken = await volmexIndexFactoryInstance.createLayerZeroVolatilityTokens(
        `${process.env.VOLATILITY_TOKEN_NAME}`,
        `${process.env.VOLATILITY_TOKEN_SYMBOL}`,
        `${process.env.INVERSE_VOLATILITY_TOKEN_NAME}`,
        `${process.env.INVERSE_VOLATILITY_TOKEN_SYMBOL}`,
        endpointAddr,
      );
    }

    const receipt = await volatilityToken.wait();

    positionTokenCreatedEvent = decodeEvents(
      volmexIndexFactoryInstance,
      filterEvents(receipt, "VolatilityTokenCreated")
    );

    console.log(
      "Volatility Index Token deployed to: ",
      positionTokenCreatedEvent[0].volatilityToken
    );
    console.log(
      "Inverse Volatility Index Token deployed to: ",
      positionTokenCreatedEvent[0].inverseVolatilityToken
    );
    volatilityTokenAddress = positionTokenCreatedEvent[0].volatilityToken;
    inverseVolatilityTokenAddress = positionTokenCreatedEvent[0].inverseVolatilityToken;
  } else {
    volatilityTokenAddress = process.env.VOLATILITY_TOKEN_ADDRESS;
    inverseVolatilityTokenAddress = process.env.INVERSE_VOLATILITY_TOKEN_ADDRESS;
  }

  console.log("Deploying VolmexProtocol...");

  let protocolInitializeArgs = [
    CollateralTokenAddress,
    volatilityTokenAddress,
    inverseVolatilityTokenAddress,
    `${process.env.MINIMUM_COLLATERAL_QTY}`,
    `${process.env.VOLATILITY_CAP_RATIO}`,
  ];

  if (process.env.PRECISION_RATIO) {
    protocolInitializeArgs.push(`${process.env.PRECISION_RATIO}`);
  }

  const volmexProtocolInstance = await upgrades.deployProxy(
    VolmexProtocolFactory,
    protocolInitializeArgs,
    {
      initializer: process.env.PRECISION_RATIO ? "initializePrecision" : "initialize",
    }
  );
  await volmexProtocolInstance.deployed();

  console.log("Volmex Protocol Proxy deployed to: ", volmexProtocolInstance.address);

  console.log("Updating Issueance and Redeem fees...");

  const feeReceipt = await volmexProtocolInstance.updateFees(
    process.env.ISSUE_FEES || 10,
    process.env.REDEEM_FEES || 30
  );
  await feeReceipt.wait();

  console.log("Updated Issueance and Redeem fees");

  proxyAdmin = await upgrades.admin.getInstance();
  const protocolImplementation = await proxyAdmin.getProxyImplementation(
    volmexProtocolInstance.address
  );

  console.log("Verifying VolmexProtocol...");

  try {
    await run("verify:verify", {
      address: protocolImplementation,
    });
  } catch (error: any) {
    console.log("Error while verifying VolmexProtocol");
  }

  console.log("Registering VolmexProtocol...");

  const registerVolmexProtocol = await volmexIndexFactoryInstance.registerIndex(
    volmexProtocolInstance.address,
    `${process.env.COLLATERAL_TOKEN_SYMBOL}`
  );

  await registerVolmexProtocol.wait();

  console.log("Registered VolmexProtocol!");

  console.log("Collateralizing ...");
  const collateral = TestCollateralFactory.attach(CollateralTokenAddress);
  await (await collateral.approve(volmexProtocolInstance.address, process.env.COLLATERAL_AMOUNT)).wait();
  await (await volmexProtocolInstance.collateralize(process.env.COLLATERAL_AMOUNT)).wait();
  console.log("Collateralized!!")
};

deploy()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("Error: ", error);
    process.exit(1);
  });

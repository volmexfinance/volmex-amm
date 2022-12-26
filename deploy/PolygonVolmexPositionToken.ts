import { ethers, upgrades, network } from "hardhat";
const LZ_ENDPOINTS = require("../constants/layerzeroEndpoints.json")

module.exports = async function () {
    const [owner] = await ethers.getSigners();
    console.log("Deployer: ", owner.address);
    console.log("Balance: ", (await owner.getBalance()).toString());
    const contract = await ethers.getContractFactory("PolygonVolmexPositionToken");
  
    console.log("Deploying upgradeable contract ...");
    
    const endpointAddr = LZ_ENDPOINTS[network.name]
    console.log(`[${network.name}] Endpoint address: ${endpointAddr}`)

    
    const instance = await upgrades.deployProxy(
        contract, 
        [`${process.env.POLYGON_TOKEN_ADDRESS}`, endpointAddr, `${process.env.WRAPPED_TOKEN_NAME}`, `${process.env.WRAPPED_TOKEN_SYMBOL}`],
        {
            initializer: "initialize",
        },
    );

    await instance.deployed();
    console.log("Deployed to PolygonVolmexPositionToken: ", (instance.address));
    
    const proxyAdmin = await upgrades.admin.getInstance();
    console.log("Proxy Implementation address: ", (await proxyAdmin.getProxyImplementation(instance.address)));
  
    // await run("verify:verify", {
    //   address: await proxyAdmin.getProxyImplementation(instance.address),
    // });
}

module.exports.tags = ["PolygonVolmexPositionToken"]

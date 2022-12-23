import { ethers, upgrades, run } from "hardhat";
const LZ_ENDPOINTS = require("../constants/layerzeroEndpoints.json")
const hre = require("hardhat");

module.exports = async function () {
    const [owner] = await ethers.getSigners();
    console.log("Deployer: ", owner.address);
    console.log("Balance: ", (await owner.getBalance()).toString());
    const contract = await ethers.getContractFactory("Layer2VolmexPositionToken");
  
    console.log("Deploying upgradeable contract ...");
    
    const endpointAddr = LZ_ENDPOINTS[hre.network.name]
    console.log(`[${hre.network.name}] Endpoint address: ${endpointAddr}`)

    const name = "Layer2VolmexPositionToken"
    const symbol = "L2VPT"
    
    const instance = await upgrades.deployProxy(
        contract, 
        [name, symbol, endpointAddr], 
        {
            initializer: "__Layer2VolmexPositionToken_init",
        },
    );

    await instance.deployed();
    console.log("Deployed to Layer2VolmexPositionToken: ", (instance.address));
    
    const proxyAdmin = await upgrades.admin.getInstance();
    console.log("Proxy Implementation address: ", (await proxyAdmin.getProxyImplementation(instance.address)));
  
    // await run("verify:verify", {
    //   address: await proxyAdmin.getProxyImplementation(instance.address),
    // });
}

module.exports.tags = ["Layer2VolmexPositionToken"]

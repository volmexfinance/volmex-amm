import "@nomiclabs/hardhat-ganache";
import "@typechain/hardhat";
import "@nomiclabs/hardhat-waffle";
import "@nomiclabs/hardhat-web3";
import "@nomiclabs/hardhat-ethers";
import "@nomiclabs/hardhat-etherscan";
import "@nomiclabs/hardhat-truffle5";
import "@nomiclabs/hardhat-ganache";
import "@openzeppelin/hardhat-upgrades";
import "@openzeppelin/hardhat-defender";

import "hardhat-gas-reporter";
import "hardhat-deploy";
import "solidity-coverage";
import "hardhat-contract-sizer";
import "./tasks";

import { config as dotEnvConfig } from "dotenv";
dotEnvConfig();

import { HardhatUserConfig } from "hardhat/types";

// You need to export an object to set up your config
// Go to https://hardhat.org/config/ to learn more
const config: HardhatUserConfig = {
  defender: {
    apiKey: `${process.env.DEFENDER_TEAM_API_KEY}`,
    apiSecret: `${process.env.DEFENDER_TEAM_API_SECRET_KEY}`,
  },
  contractSizer: {
    alphaSort: true,
    runOnCompile: true,
    disambiguatePaths: false,
  },
  defaultNetwork: "hardhat",
  solidity: {
    compilers: [
      {
        version: "0.8.17",
        settings: {
          optimizer: {
            enabled: true,
            runs: 2000,
          },
        },
      },
    ],
  },
  networks: {
    hardhat: {
      allowUnlimitedContractSize: false,
      forking: {
        enabled: true,
        url: `https://polygon-mainnet.g.alchemy.com/v2/${process.env.POLYGON_MAINNET_ALCHEMY_API_KEY}`,
        blockNumber: 34033365,
      },
    },
    localhost: {
      url: "http://127.0.0.1:8545", // same address and port for both Buidler and Ganache node
      accounts: [
        /* will be provided by ganache */
      ],
      gas: 8000000,
      gasPrice: 1,
    },
    goerli: {
      url: `https://eth-goerli.g.alchemy.com/v2/${process.env.GOERLI_ALCHEMY_API_KEY}`,
      accounts: [`0x${process.env.PRIVATE_KEY}`],
      throwOnTransactionFailures: true,
      loggingEnabled: true,
      gasMultiplier: 1.5,
      timeout: 36000000,
    },
    mumbai: {
      url: `https://polygon-mumbai.g.alchemy.com/v2/${process.env.POLYGON_TESTNET_ALCHEMY_API_KEY}`,
      accounts: [`0x${process.env.PRIVATE_KEY}`],
      throwOnTransactionFailures: true,
      loggingEnabled: true,
      gas: 5000000,
      gasPrice: 10000000000,
      blockGasLimit: 8000000,
    },
    polygon: {
      url: `https://polygon-mainnet.g.alchemy.com/v2/${process.env.POLYGON_MAINNET_ALCHEMY_API_KEY}`,
      accounts: [`0x${process.env.PRIVATE_KEY}`],
      throwOnTransactionFailures: true,
      loggingEnabled: true,
      gas: 5000000,
      blockGasLimit: 8000000,
      timeout: 18000000,
    },
    "arbitrum-goerli": {
      url: `https://arb-goerli.g.alchemy.com/v2/${process.env.ARBITRUM_TESTNET_ALCHEMY_API_KEY}`,
      accounts: [`0x${process.env.PRIVATE_KEY}`],
      throwOnTransactionFailures: true,
      loggingEnabled: true,
      timeout: 18000000,
      chainId: 421613,
    }
  },
  etherscan: {
    // Your API key for Etherscan
    // Obtain one at https://etherscan.io/
    apiKey: process.env.ETHERSCAN_API_KEY,
  },
  gasReporter: {
    currency: "USD",
    gasPrice: 21,
  },
  typechain: {
    outDir: "typechain",
    target: "ethers-v5",
  },
};

export default config;

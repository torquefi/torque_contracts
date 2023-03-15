const dotenv = require("dotenv");
dotenv.config();

import { HardhatUserConfig, task } from "hardhat/config";
require("@openzeppelin/hardhat-upgrades");
import "@nomicfoundation/hardhat-toolbox";

const {
  PRIVATE_KEY,
  API_KEY_BSC_TESTNET,
  API_KEY_GOERLI,
  API_KEY_ETH,
  API_KEY_BSC_MAINNET,
} = process.env;
// This is a sample Hardhat task. To learn how to create your own go to
// https://hardhat.org/guides/create-task.html
task("accounts", "Prints the list of accounts", async (taskArgs, hre) => {
  const accounts = await hre.ethers.getSigners();

  for (const account of accounts) {
    console.log(account.address);
  }
});

// You need to export an object to set up your config
// Go to https://hardhat.org/config/ to learn more

const config: HardhatUserConfig = {
  etherscan: {
    apiKey: {
      bscTestnet: `${API_KEY_BSC_TESTNET}`,
      goerli: `${API_KEY_GOERLI}`,
      mainnet: `${API_KEY_ETH}`, //eth
      bsc: `${API_KEY_BSC_MAINNET}`, //bsc
    },
  },
  networks: {
    localhost: {
      url: "http://127.0.0.1:8545",
    },
    hardhat: {},
    goerli: {
      url: `https://goerli.infura.io/v3/${API_KEY_GOERLI}`,
      chainId: 5,
      accounts: [`0x${PRIVATE_KEY}`],
    },
    testnet: {
      url: "https://data-seed-prebsc-1-s1.binance.org:8545",
      chainId: 97,
      accounts: [`0x${PRIVATE_KEY}`],
    },
    mainnet: {
      url: "https://bsc-dataseed.binance.org/",
      chainId: 56,
      accounts: [`0x${PRIVATE_KEY}`],
    },
    rinkeby: {
      url: `https://rinkeby.infura.io/v3/${API_KEY_ETH}`,
      accounts: [`0x${PRIVATE_KEY}`],
    },
    eth: {
      url: `https://eth-mainnet.gateway.pokt.network/v1/${API_KEY_ETH}`,
      chainId: 1,
      accounts: [`0x${PRIVATE_KEY}`],
    },
    arbi: {
      url: "https://arb1.arbitrum.io/rpc",
      chainId: 42161,
      accounts: [`0x${PRIVATE_KEY}`],
    },
    testarbi: {
      url: "https://goerli-rollup.arbitrum.io/rpc",
      chainId: 421613,
      accounts: [`0x${PRIVATE_KEY}`],
    },
    matic: {
      url: "https://matic-mumbai.chainstacklabs.com/",
      accounts: [`0x${PRIVATE_KEY}`],
    },
  },
  solidity: {
    version: "0.8.15",
    settings: {
      optimizer: process.env["OPTIMIZER_DISABLED"]
        ? { enabled: false }
        : {
            enabled: true,
            runs: 1,
            details: {
              yulDetails: {
                optimizerSteps:
                  "dhfoDgvulfnTUtnIf [xa[r]scLM cCTUtTOntnfDIul Lcul Vcul [j] Tpeul xa[rul] xa[r]cL gvif CTUca[r]LsTOtfDnca[r]Iulc] jmul[jul] VcTOcul jmul",
              },
            },
          },
      outputSelection: {
        "*": {
          "*": ["evm.deployedBytecode.sourceMap"],
        },
      },
      viaIR: process.env["OPTIMIZER_DISABLED"] ? false : true,
    },
  },
  mocha: {
    timeout: 20000,
  },
};

export default config;

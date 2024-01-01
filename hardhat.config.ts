const dotenv = require("dotenv");
dotenv.config();

import { HardhatUserConfig, task } from "hardhat/config";
require("@openzeppelin/hardhat-upgrades");
import "@nomicfoundation/hardhat-toolbox";

const {
  PRIVATE_KEY,
  API_KEY_ARBITRUM_ONE,
  API_KEY_ARBITRUM_GOERLI,
  TENDERLY_PROJECT_NAME,
  TENDERLY_USERNAME,
} = process.env;

task("accounts", "Prints the list of accounts", async (taskArgs, hre) => {
  const accounts = await hre.ethers.getSigners();

  for (const account of accounts) {
    console.log(account.address);
  }
});

const config: HardhatUserConfig = {
  paths: {
    sources: "./contracts/TorqueProtocol",
  },
  etherscan: {
    apiKey: {
      arbitrumGoerli: `${API_KEY_ARBITRUM_GOERLI}`,
      arbitrumOne: `${API_KEY_ARBITRUM_ONE}`,
    },
  },
  networks: {
    localhost: {
      url: "http://127.0.0.1:8545",
    },
    hardhat: {},
    arbitrumMainnet: {
      url: "https://arb1.arbitrum.io/rpc",
      chainId: 42161,
      accounts: [`0x${PRIVATE_KEY}`],
    },
    arbitrumGoerli: {
      url: "https://goerli-rollup.arbitrum.io/rpc",
      chainId: 421613,
      accounts: [`0x${PRIVATE_KEY}`],
    },
    tenderlyFork: {
      url: `https://rpc.tenderly.co/fork/b8cef826-3d88-42f1-bc3a-82d34962ab5a`,
      chainId: 42161, // Arbitrum One fork
      accounts: [`0x${PRIVATE_KEY}`],
      gasPrice: 0,
      gas: 12000000,
      headers: {
        "x-tenderly-project": TENDERLY_PROJECT_NAME,
        "x-tenderly-username": TENDERLY_USERNAME
      }
  },
  solidity: {
    compilers: [
        {
          version: "0.8.6",
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
        {
          version: "0.8.9",
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
        {
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
        {
          version: "0.8.20",
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
      ],
    },
    mocha: {
      timeout: 20000,
    },
  },
};

export default config;

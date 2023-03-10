const dotenv = require('dotenv')
dotenv.config()
require("@nomiclabs/hardhat-waffle");
require("@nomiclabs/hardhat-etherscan");
require('@nomiclabs/hardhat-ethers');
require('@openzeppelin/hardhat-upgrades');

const { PRIVATE_KEY } = process.env;
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

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
module.exports = {
  defaultNetwork: "goerli",
  etherscan: {
    apiKey: {
      bscTestnet: `${API_KEY_BSC_TESTNET}`,
      goerli: `${API_KEY_GOERLI}`,
      mainnet: `${API_KEY_ETH}`, //eth
      bsc: `${API_KEY_BSC_MAINNET}` //bsc
    }
  },
  networks: {
    localhost: {
      url: "http://127.0.0.1:8545"
    },
    hardhat: {
    },
    goerli: {
      url: "https://goerli.infura.io/v3/43885af4abc848f0a04f9fdabd95ea43",
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
      url: "https://rinkeby.infura.io/v3/78e016a8a20d4c1e99944ebadf6e732e",
      accounts: [`0x${PRIVATE_KEY}`],
    },
    eth: {
      url: "https://eth-mainnet.gateway.pokt.network/v1/5f3453978e354ab992c4da79",
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
    }
  },
  solidity: {
    compilers: [
      {
        version: "0.8.16",
      },
      {
        version: "0.8.5",
      },
      {
        version: "0.8.0",
      },
      {
        version: "0.8.17",
        settings: {},
      },
    ],
    settings: {
      optimizer: {
        enabled: true
      }
    }
  },
  mocha: {
    timeout: 20000
  }
};
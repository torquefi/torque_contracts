# Torque Protocol

[Website](https://torque.fi) | [Twitter](https://twitter.com/torquefi) | [Telegram](https://t.me/torquefi) | [Docs](https://docs.torque.fi)


# Setup

```sh
$ npm i -j hardhat
```

## Usage
## PLEASE FIX 'PS CHECK' (FIND) BEFORE BUILD
```sh
$ npx hardhat compile // Compile Code
$ npx hardhat node // Start localhost test accounts
$ npx hardhat test --localhost // Local Deployment & Testing
$ npx hardhat test scripts/NFT-deploy.js --network rinkeby  // RinkeBy Testnet Deployment
$ npx hardhat test scripts/NFT-deploy.js --network mainnet  // Main-net Deployment
$ npx hardhat verify --network goerli ContractAddress ConstructorArg1 ConstructorArg2 ....
```
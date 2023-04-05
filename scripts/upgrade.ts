
const { ethers } = require('hardhat');
const PROXY_CONTRACT_ADDRESS = "0x22463e8a467cff8499886a2ca0dde58780b6542a"
async function main() {
   
  const UpdateContract = await ethers.getContractFactory("Borrow");
  await upgrades.upgradeProxy(PROXY_CONTRACT_ADDRESS,UpdateContract);

}
// npx hardhat verify --network testnet 0x00dbcd95b15b8e30b4786756d1439a7bc98fea11 

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
});

const { ethers } = require('hardhat');
const PROXY_CONTRACT_ADDRESS = "0xbA32f8febc4aFB1Ee9A92548c9deb8989F37Daf4"
async function main() {
   
  const UpdateContract = await ethers.getContractFactory("ETHBorrow");
  await upgrades.upgradeProxy(PROXY_CONTRACT_ADDRESS,UpdateContract);

}
// npx hardhat verify --network testnet 0x00dbcd95b15b8e30b4786756d1439a7bc98fea11 

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
});

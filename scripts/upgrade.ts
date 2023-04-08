
const { ethers } = require('hardhat');
const PROXY_CONTRACT_ADDRESS = "0x3744d58727aCeCdCef28E94136eDb7C1af2DD802"
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

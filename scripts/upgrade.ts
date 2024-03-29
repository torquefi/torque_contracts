const { ethers } = require('hardhat');
const PROXY_CONTRACT_ADDRESS = "0xD6047Dc4258aDFf8F35dA52DAE16f04cA5E0F16B"
async function main() {
   
  const UpdateContract = await ethers.getContractFactory("BTCBorrow");
  await upgrades.upgradeProxy(PROXY_CONTRACT_ADDRESS,UpdateContract);

}
// npx hardhat verify --network testnet 0x00dbcd95b15b8e30b4786756d1439a7bc98fea11 

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
});

import { ethers } from "hardhat";

async function main() {
  const testGMX = await ethers.deployContract("TestGMXV2", [
    "0x82aF49447D8a07e3bd95BD0d56f35241523fBab1", // WETH
    "0x7c68c7866a64fa2160f78eeae12217ffbf871fa8", // GMX Exchange
    "0x70d95587d40A2caf56bd97485aB3Eec10Bee6336", // GM Token
    "0xaf88d065e77c8cC2239327C5EDb3A432268e5831", // USDC Token
    "F89e77e8Dc11691C9e8757e84aaFbCD8A67d7A55", // Deposit Vault
    "0x0628D46b5D145f183AdB6Ef1f2c97eD1C4701C55", // Withdraw Vault
  ]);

  await testGMX.deployed();

  console.log(`testGMX deployed at ${testGMX.address}`);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});

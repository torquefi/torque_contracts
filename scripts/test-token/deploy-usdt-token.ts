import { ethers } from "hardhat";

async function main() {
  const usdt = await ethers.deployContract("Token", ["USDT Token", "USDT"]);

  await usdt.deployed();

  console.log(`USDT token deployed at ${usdt.address}`);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});

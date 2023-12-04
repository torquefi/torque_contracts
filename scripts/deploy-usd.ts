import { ethers } from "hardhat";

async function main() {
  const usd = await ethers.deployContract("USD", []);

  await usd.deployed();

  console.log(`usd deployed at ${usd.target}`);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});

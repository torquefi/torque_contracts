import { ethers } from "hardhat";

async function main() {
  const USD = await ethers.getContractFactory("MockUSD");
  const usd = await USD.deploy();

  await usd.deployed();

  console.log(`usd deployed at ${usd.address}`);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});

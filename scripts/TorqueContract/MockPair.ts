import { ethers } from "hardhat";

async function main() {
  const PAIR = await ethers.getContractFactory("MockPair");
  const pair = await PAIR.deploy();

  await pair.deployed();

  console.log(`pair deployed at ${pair.address}`);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});

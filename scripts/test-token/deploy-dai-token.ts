import { ethers } from "hardhat";

async function main() {
  const dai = await ethers.deployContract("Token", ["DAI Token", "DAI"]);

  await dai.deployed();

  console.log(`DAI token deployed at ${dai.address}`);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});

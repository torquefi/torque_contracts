import { ethers } from "hardhat";

async function main() {
  const TestContract = await ethers.getContractFactory("MockToken");
  const testContract = await TestContract.deploy("TestToken", "USDTest", 18);

  await testContract.deployed();

  console.log(`testContract deployed at ${testContract.address}`);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});

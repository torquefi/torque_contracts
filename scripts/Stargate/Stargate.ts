import { ethers } from "hardhat";

async function main() {
  const StargateContract = await ethers.getContractFactory("MockToken");
  const stargateContract = await StargateContract.deploy("Stargate", "STG", 18);

  await stargateContract.deployed();

  console.log(`stargateContract deployed at ${stargateContract.address}`);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});

import { ethers } from "hardhat";

async function main() {
  const gmx = await ethers.deployContract("Token", ["GMX Token", "GMX"]);

  await gmx.waitForDeployment();

  console.log(`GMX token deployed at ${gmx.target}`);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});

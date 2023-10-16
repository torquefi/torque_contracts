import { ethers } from "hardhat";

async function main() {
  const faucet = await ethers.deployContract("Faucet", []);

  await faucet.waitForDeployment();

  console.log(`Faucet contract is deployed at ${faucet.target}`);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});

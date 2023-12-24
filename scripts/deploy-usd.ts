import { ethers } from "hardhat";

async function main() {
  const tusd = await ethers.deployContract("TUSD", []);

  await tusd.deployed();

  console.log(`tusd deployed at ${tusd.target}`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});

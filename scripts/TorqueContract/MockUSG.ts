import { ethers } from "hardhat";

async function main() {
  const USG = await ethers.getContractFactory("MockUSG");
  const usg = await USG.deploy();

  await usg.deployed();

  console.log(`usg deployed at ${usg.address}`);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});

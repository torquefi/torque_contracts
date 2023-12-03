import { ethers } from "hardhat";

async function main() {
  const comp = await ethers.deployContract("Token", ["COMP Token", "COMP"]);

  await comp.deployed();

  console.log(`COMP token deployed at ${comp.address}`);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});

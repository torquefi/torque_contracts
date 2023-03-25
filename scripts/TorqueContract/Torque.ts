import { ethers } from "hardhat";

async function main() {
  const TorqueContract = await ethers.getContractFactory("Torque");
  const torqueContract = await TorqueContract.deploy("Torque", "TORQ");

  await torqueContract.deployed();

  console.log(`torque deployed at ${torqueContract.address}`);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});

import { ethers } from "hardhat";

async function main() {
  const STorqueContract = await ethers.getContractFactory("StakingTorque");
  const sTorqueContract = await STorqueContract.deploy();

  await sTorqueContract.deployed();

  console.log(`staking torque deployed at ${sTorqueContract.address}`);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});

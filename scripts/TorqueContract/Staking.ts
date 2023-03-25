import { ethers } from "hardhat";

async function main() {
  const StakingContract = await ethers.getContractFactory("Staking");
  const stakingContract = await StakingContract.deploy(
    "0x4Aa7aed6BDa411534801D1d64227Bc1CFA79A1Dd", // torque token
    "0x6f780722d64fE2d3b3FeB15c4F2E0D92f64299a1" //s torque token
  );

  await stakingContract.deployed();

  console.log(`staking deployed at ${stakingContract.address}`);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});

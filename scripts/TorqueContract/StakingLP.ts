import { ethers } from "hardhat";

async function main() {
  const StakingLPContract = await ethers.getContractFactory("StakingLP");
  const stakingLPContract = await StakingLPContract.deploy(
    "0x0000000000000000000000000000000000000000", // pair
    "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D", // router
    "0x4Aa7aed6BDa411534801D1d64227Bc1CFA79A1Dd", // torque token
    "0x6f780722d64fE2d3b3FeB15c4F2E0D92f64299a1" // s torque token
  );

  await stakingLPContract.deployed();

  console.log(`staking LP deployed at ${stakingLPContract.address}`);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});

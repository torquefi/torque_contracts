import { ethers } from "hardhat";

async function main() {
  const LPStakingContract = await ethers.getContractFactory("LPStaking");
  const lpStakingContract = await LPStakingContract.deploy(
    "0x1a26479d3A4bb6b3B5d8014dDC0F069174B2A7A9", // STG Token
    "1000000000000000000", // emission per block
    25311234, // start block
    "1000000000" // bonus end block
  );

  await lpStakingContract.deployed();

  console.log(`lpStakingContract deployed at ${lpStakingContract.address}`);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});

import { ethers } from "hardhat";

async function main() {
  const LPStakingContract = await ethers.getContractFactory("LPStaking");
  const lpStakingContract = await LPStakingContract.deploy(
    "0xd22b80AbE59661e5aCdBEa247D08A24123df45dF", // STG Token
    "1000000000000000000", // emission per block
    8859289, // start block
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

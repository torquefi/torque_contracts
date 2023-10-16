import { ethers } from "hardhat";

async function main() {
  const StakingContract = await ethers.getContractFactory("Staking");
  const stakingContract = await StakingContract.deploy(
    "0x7783c490B6D12E719A4271661D6Eb03539eB9BC9", // torque token
    "0x93797Bc71Ff7964A5d02cfC69FfEE04dFCb5fCAb" //s torque token
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

import { ethers } from "hardhat";

async function main() {
  const RewardUtil = await ethers.getContractFactory("RewardUtil");
  const reward = await upgrades.deployProxy(RewardUtil, [], {
    initializer: "initialize",
  });
  const rewardResult = await reward.deployed();

  console.log(
    ` deployed to ${rewardResult.address}`
  );
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});


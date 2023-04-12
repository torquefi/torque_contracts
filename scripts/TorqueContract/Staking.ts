import { ethers } from "hardhat";

async function main() {
  const StakingContract = await ethers.getContractFactory("Staking");
  const stakingContract = await StakingContract.deploy(
    "0xB98EfE47A7Ed24CBAF02318BCe8e6413A2d11a49", // torque token
    "0xD373522e549a29A7E46988ad5dD151Ea702C82E5" //s torque token
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

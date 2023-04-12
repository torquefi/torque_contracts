import { ethers } from "hardhat";

async function main() {
  const StakingLPContract = await ethers.getContractFactory("StakingLP");
  const stakingLPContract = await StakingLPContract.deploy(
    "0x0000000000000000000000000000000000000000", // pair
    "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D", // router
    "0xB98EfE47A7Ed24CBAF02318BCe8e6413A2d11a49", // torque token
    "0xD373522e549a29A7E46988ad5dD151Ea702C82E5" //s torque token
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

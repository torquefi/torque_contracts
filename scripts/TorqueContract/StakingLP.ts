import { ethers } from "hardhat";

async function main() {
  const StakingLPContract = await ethers.getContractFactory("StakingLP");
  // const stakingLPContract = await StakingLPContract.deploy(
  //   "0x88da624eD11CfAf1967B1D19B090636080Ece2f5", // pair
  //   "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D", // router
  //   "0xB98EfE47A7Ed24CBAF02318BCe8e6413A2d11a49", // torque token
  //   "0xD373522e549a29A7E46988ad5dD151Ea702C82E5" //s torque token
  // );

  const stakingLPContract = await StakingLPContract.deploy(
    "0x7d822102aDD1AC45E1941d6959e4c5D4288cD836", // pair
    "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D", // router
    "0x7783c490B6D12E719A4271661D6Eb03539eB9BC9", // torque token
    "0x93797Bc71Ff7964A5d02cfC69FfEE04dFCb5fCAb" //s torque token
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

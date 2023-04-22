import { ethers } from "hardhat";

async function main() {
  const BoostContract = await ethers.getContractFactory("Boost");
  const boostContract = await BoostContract.deploy(
    "0xA81D21c0A87F2A6A7618B75e45ad9A7731164207", // LP Staking
    "0xd22b80AbE59661e5aCdBEa247D08A24123df45dF", // Stargaate Token
    "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D", // Router
    "0xB4FBF271143F4FBf7B91A5ded31805e42b2208d6" // WETH
  );

  await boostContract.deployed();

  console.log(`boostContract deployed at ${boostContract.address}`);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});

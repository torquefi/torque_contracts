import { ethers } from "hardhat";

async function main() {
  const BoostContract = await ethers.getContractFactory("Boost");
  const boostContract = await BoostContract.deploy(
    "0xb7A9088FD945e4a6a1A43F8A1322B4c1800BC5C3", // LP Staking
    "0x1a26479d3A4bb6b3B5d8014dDC0F069174B2A7A9", // Stargaate Token
    "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D", // Router
    "0xEe01c0CD76354C383B8c7B4e65EA88D00B06f36f" // WETH
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

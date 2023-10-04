import { ethers } from "hardhat";

async function main() {
  const BoostContract = await ethers.getContractFactory("Boost");
  const boostContract = await BoostContract.deploy(
    "0x5168f92eD68Bd7e1b4e7a43aa5747Ffd5011a89e", // LP Staking
    "0xfE8EBe40dC9E399F4D6FaEfCC36e5749411BC58C", // Stargaate Token
    "0xE592427A0AEce92De3Edee1F18E0157C05861564" // Router
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

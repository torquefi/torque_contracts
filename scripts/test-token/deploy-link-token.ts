import { ethers } from "hardhat";

async function main() {
  const btc = await ethers.deployContract("Token", ["LINK Token", "LINK"]);

  await btc.deployed();

  console.log(`LINK token deployed at ${btc.address}`);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});

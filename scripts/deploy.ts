import { ethers } from "hardhat";

async function main() {
  const Borrow = await ethers.getContractFactory("Borrow");
  const borrow = await Borrow.deploy(
    "0x3EE77595A8459e93C2888b13aDB354017B198188",
    "0xAAD4992D949f9214458594dF92B44165Fb84dC19",
    "0x07865c6E87B9F70255377e024ace6630C1Eaa37F"
  );

  await borrow.deployed();

  console.log(` deployed to ${borrow.address}`);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});

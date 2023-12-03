import { ethers } from "hardhat";

async function main() {
  const testStargate = await ethers.deployContract("TestStargate", [
    "0xbf22f0f184bccbea268df387a49ff5238dd23e40", // Stargate Router ETH
    "0x53bf833a5d6c4dda888f69c22c88c9f356a41614", // Stargate Router
    "0xB4FBF271143F4FBf7B91A5ded31805e42b2208d6", // WETH
  ]);

  await testStargate.deployed();

  console.log(`TestStargate deployed at ${testStargate.address}`);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});

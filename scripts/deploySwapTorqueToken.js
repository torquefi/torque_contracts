// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// You can also run a script with `npx hardhat run <script>`. If you do that, Hardhat
// will compile your contracts, add the Hardhat Runtime Environment's members to the
// global scope, and execute the script.

// - WBTC/WETH, SWAP FEE 3000
// - USDC/WETH, SWAP FEE 3000
// - USDC/TUSD, SWAP FEE 100
// - TORQ/WETH, SWAP FEE 3000


const hre = require("hardhat");
// npx hardhat verify --network arbitrum 0xea15bd7a9382fA7dcDED328cBBCFDEC6c397c531 "0xC4B853F10f8fFF315F21C6f9d1a1CEa8fbF0Df01"
async function deploySwapTorqueToken() {

  const SwapTorque = await hre.ethers.getContractFactory("SwapTorqueToken");
  let swapTorque;
  console.log("SwapTorque factory created.");
  try{
    swapTorque = await SwapTorque.deploy("0xC4B853F10f8fFF315F21C6f9d1a1CEa8fbF0Df01");
  }
  catch (error) {
    console.error("Error deploying SwapTorque:", error);
    process.exit(1);
  }
  console.log("SwapTorque Contract Address", swapTorque.target);
  return swapTorque;
}

// We recommend this pattern to be able to use async/await everywhere

deploySwapTorqueToken().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});

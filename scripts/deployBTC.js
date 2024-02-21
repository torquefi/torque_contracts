// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// You can also run a script with `npx hardhat run <script>`. If you do that, Hardhat
// will compile your contracts, add the Hardhat Runtime Environment's members to the
// global scope, and execute the script.
const hre = require("hardhat");

async function deployBorrowBTCContract() {

  const BTCBorrow = await hre.ethers.getContractFactory("BTCBorrow");
  let btcBorrow;
  console.log("BTCBorrow factory created.");
  try{
      btcBorrow = await BTCBorrow.deploy("0xC4B853F10f8fFF315F21C6f9d1a1CEa8fbF0Df01", 
    "0x9c4ec768c28520B50860ea7a15bd7213a9fF58bf", 
    "0x88730d254A2f7e6AC8388c3198aFd694bA9f7fae", 
    "0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f",
    "0xaf88d065e77c8cC2239327C5EDb3A432268e5831",
    "0xbdE8F31D2DdDA895264e27DD990faB3DC87b372d",
    "0x867bF0476655Cf05934869B449a0be0ED534eA60",
    "0xf7F6718Cf69967203740cCb431F6bDBff1E0FB68",
    "0x0f773B3d518d0885DbF0ae304D87a718F68EEED5",
    1);
  }
  catch (error) {
    console.error("Error deploying BTCBorrow:", error.message);
    process.exit(1);
  }
  console.log("BTC Borrow Contract Address", btcBorrow.target);
  return btcBorrow;
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
deployBorrowBTCContract().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});

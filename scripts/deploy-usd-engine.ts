import { ethers } from "hardhat";

async function main() {
  const USDEngine = await ethers.deployContract("USDEngine", [
    [
      "0x25A4f6d1A02b31e5E1EB7ca37da31c911a9A8c69", //  BTC
      "0xEe01c0CD76354C383B8c7B4e65EA88D00B06f36f", //  WETH
      "0x4F13EC3088396821d894039C39b267cda4c19B8E", //  USDC
      "0xe1fa7ed66b91889Fd0F0d4F4Ff1d3444166b5B5B", //  USDT
      "0x8BFa226A9a1817816a92D416868790385bC7E297", //  DAI
      "0x8FB1E3fC51F3b789dED7557E680551d93Ea9d892", //  USDC Compound
    ],
    [
      "0x6550bc2301936011c1334555e62A87705A81C12C", //  Price Feed BTC-USD
      "0x62CAe0FA2da220f43a51F86Db2EDb36DcA9A5A08", //  Price Feed ETH-USD
      "0x1692Bdd32F31b831caAc1b0c9fAF68613682813b", //  Price Feed USDC-USD
      "0x0a023a3423D9b27A0BE48c768CCF2dD7877fEf5E", //  Price Feed USDT-USD
      "0x103b53E977DA6E4Fa92f76369c8b7e20E7fb7fe1", //  Price Feed DAI-USD
      "0x1692Bdd32F31b831caAc1b0c9fAF68613682813b", //  Price Feed USDCCompound-USD
    ],
    [80, 80, 100, 100, 100, 100], //  liquidation thresholds
    "0xf740359877183aD9647fa2924597B9112877Cb2d",
  ]);

  await USDEngine.waitForDeployment();

  console.log(`usd engine deployed at ${USDEngine.target}`);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});

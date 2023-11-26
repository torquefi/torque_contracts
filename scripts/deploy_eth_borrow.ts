import { ethers } from "hardhat";

async function main() {
  const Borrow = await ethers.getContractFactory("ETHBorrow");
  //_comet, _cometReward, _asset, _baseAsset, bulker,  _engine,  _usd,  _treasury,  _rewardUtil,  _rewardToken
  const borrow = await upgrades.deployProxy(Borrow, ['0x9c4ec768c28520B50860ea7a15bd7213a9fF58bf','0x88730d254A2f7e6AC8388c3198aFd694bA9f7fae','0x82af49447d8a07e3bd95bd0d56f35241523fbab1','0xaf88d065e77c8cC2239327C5EDb3A432268e5831', '0xbdE8F31D2DdDA895264e27DD990faB3DC87b372d', '0x3c716812B02aC5Ea432b153B134770e7f78E6542', '0xB50B92Fa490AA2366751F04b52C5f3350AD4AC16',  '0x10Df08c7265EBBa82Bd0619aA3f2C2B5621e140C','0xba32a1F10Be022210d9EBC7FFa191a7023cb3601','0xaf88d065e77c8cC2239327C5EDb3A432268e5831'], {
    initializer: "initialize",
  });
  const borrowResult = await borrow.deployed();

  console.log(
    ` deployed to ${borrowResult.address}`
  );
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});


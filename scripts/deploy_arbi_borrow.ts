import { ethers } from "hardhat";

async function main() {

  const Borrow = await ethers.getContractFactory("ARBI_Borrow");
  const borrow = await upgrades.deployProxy(Borrow, ['0x1d573274E19174260c5aCE3f2251598959d24456','0x22d5e2dE578677791f6c90e0110Ec629be9d5Fb5','0x8FB1E3fC51F3b789dED7557E680551d93Ea9d892','0x987350Af5a17b6DdafeB95E6e329c178f44841d7', '0xe722eAbC78561b46D951e8c23f1a12944e02b440', '0xf740359877183aD9647fa2924597B9112877Cb2d'], {
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


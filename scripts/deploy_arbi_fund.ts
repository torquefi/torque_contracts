import { ethers } from "hardhat";

async function main() {

  const Fund = await ethers.getContractFactory("CompoundFund");
  const fund = await upgrades.deployProxy(Fund, ['0x1d573274E19174260c5aCE3f2251598959d24456','0x8FB1E3fC51F3b789dED7557E680551d93Ea9d892'], {
    initializer: "initialize",
  });
  const fundResult = await fund.deployed();

  console.log(
    ` deployed to ${fundResult.address}`
  );
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});


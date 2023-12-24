import { ethers } from "hardhat";

async function main() {

  const Fund = await ethers.getContractFactory("CompoundFund");
  const fund = await upgrades.deployProxy(Fund, ['0x9c4ec768c28520B50860ea7a15bd7213a9fF58bf','0xaf88d065e77c8cC2239327C5EDb3A432268e5831'], {
    initializer: "initialize",
  });
  const fundResult = await fund.deployed();

  console.log(
    ` deployed to ${fundResult.address}`
  );
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});


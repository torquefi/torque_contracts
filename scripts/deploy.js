const { ethers } = require('hardhat');

async function main() {
  const Ctr = await ethers.getContractFactory("Torque");
  const ctr = await Ctr.deploy();
  const ctrResult = await ctr.deployed();
  console.log("Success when deploy contract: %s", ctrResult.address);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
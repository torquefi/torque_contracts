import { ethers } from "hardhat";

async function main() {

  const Borrow = await ethers.getContractFactory("BTCBorrow");
  const borrow = await upgrades.deployProxy(Borrow, ['0x3EE77595A8459e93C2888b13aDB354017B198188','0xef9e070044d62C38D2e316146dDe92AD02CF2c2c','0xAAD4992D949f9214458594dF92B44165Fb84dC19','0x07865c6E87B9F70255377e024ace6630C1Eaa37F', '0xf82AAB8ae0E7F6a2ecBfe2375841d83AeA4cb9cE', '0x5c51Fb12f845569369A838e2c6868Cb06d8b35De', '0x2098025567E0511Ea7db7F369347bcD29B8DFB30', '0x0f773B3d518d0885DbF0ae304D87a718F68EEED5','0xa6e8bAf56d88CbD6cC4f238D1443A852109d548d','0x07865c6E87B9F70255377e024ace6630C1Eaa37F'], {
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


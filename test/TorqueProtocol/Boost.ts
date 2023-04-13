import { time, loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";
import { expect } from "chai";
import { ethers, network } from "hardhat";
import { BigNumber } from "ethers";
const {
  getAddr,
  deployNew,
  getCurrentBlock,
  mineNBlocks,
  callAsContract,
} = require("./../StargateUtils/helpers");

describe("Boost Smart Contract", () => {
  async function fixtureDeployAndInitStub() {
    // Contracts are deployed using the first signer/account by default
    const [owner, alice, bob, daniel] = await ethers.getSigners();

    const TokenContract = await ethers.getContractFactory("Torque");
    const tokenContract = await TokenContract.deploy("Torque", "TORQ");

    const STorqueTokenContract = await ethers.getContractFactory(
      "StakingTorque"
    );
    const sTorqueTokenContract = await STorqueTokenContract.deploy();

    const StakingContract = await ethers.getContractFactory("Staking");
    const stakingContract = await StakingContract.deploy(
      tokenContract.address,
      sTorqueTokenContract.address
    );

    await stakingContract.setEnabled(true);
    await sTorqueTokenContract.grantMintRole(stakingContract.address);
    await sTorqueTokenContract.grantBurnRole(stakingContract.address);

    return {
      owner,
      alice,
      bob,
      daniel,
      tokenContract,
      sTorqueTokenContract,
      stakingContract,
    };
  }

  describe("Check normal Deposit and Withdraw in Boost", () => {
    let owner, alice, badUser1, fakeContract, mockToken, lpStaking;
    let chainId,
      startBlock,
      bonusEndBlock,
      emissionsPerBlock,
      poolId,
      allocPoint,
      depositAmt,
      stargateToken,
      boostContract,
      router;

    before(async function () {
      ({ owner, alice, badUser1, fakeContract } = await getAddr(ethers));
      poolId = 0;
      chainId = 1;
      allocPoint = 3;
      bonusEndBlock = 1000000000;
      emissionsPerBlock = "1000000000000000000";
      depositAmt = BigNumber.from("1000000000000000000");
    });

    beforeEach(async function () {
      startBlock = (await getCurrentBlock()) + 3;
      stargateToken = await deployNew("MockToken", ["Token", "TKN", 18]);
      lpStaking = await deployNew("LPStaking", [
        stargateToken.address,
        emissionsPerBlock,
        startBlock,
        bonusEndBlock,
      ]);
      mockToken = await deployNew("MockToken", ["Token", "TKN", 18]);

      await mockToken.transfer(lpStaking.address, "10000000000000000000000");
      router = await deployNew("MockSwap", []);
      boostContract = await deployNew("Boost", [
        lpStaking.address,
        stargateToken.address,
        router.address,
      ]);
    });

    it("Deposit successfully", async () => {
      await lpStaking.add(allocPoint, mockToken.address);
      await mockToken.approve(
        boostContract.address,
        "100000000000000000000000"
      );

      await boostContract.deposit(
        mockToken.address,
        "100000000000000000000000"
      );
    });

    it("Withdraw boost successfully", async () => {
      await lpStaking.add(allocPoint, mockToken.address);
      await mockToken.approve(
        boostContract.address,
        "100000000000000000000000"
      );

      await boostContract.deposit(
        mockToken.address,
        "100000000000000000000000"
      );

      await boostContract.withdraw(
        mockToken.address,
        "100000000000000000000000"
      );
    });
  });
});

import { time, loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";
import { expect } from "chai";
import { ethers, network } from "hardhat";
import { BigNumber } from "ethers";

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
    it("Deposit successfully", async () => {});
  });
});

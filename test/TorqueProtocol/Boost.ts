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
    let owner, alice, badUser1, fakeContract, mockToken, lpStaking, weth;
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
      weth = await deployNew("WETH", []);
      boostContract = await deployNew("Boost", [
        lpStaking.address,
        stargateToken.address,
        router.address,
        weth.address,
      ]);
    });

    it("Deposit successfully", async () => {
      await lpStaking.add(allocPoint, mockToken.address);
      await mockToken.approve(boostContract.address, "10000000000000000000");

      await boostContract.deposit(mockToken.address, "10000000000000000000");
    });

    it("Withdraw boost successfully", async () => {
      await lpStaking.add(allocPoint, mockToken.address);
      await mockToken.approve(boostContract.address, "10000000000000000000");

      await boostContract.deposit(mockToken.address, "10000000000000000000");

      await boostContract.withdraw(mockToken.address, "10000000000000000000");
    });

    it("Compound and check reward success", async () => {
      await lpStaking.add(allocPoint, mockToken.address);
      await mockToken.approve(boostContract.address, "10000000000000000000");
      await boostContract.deposit(mockToken.address, "10000000000000000000");
      await stargateToken.transfer(lpStaking.address, "100000000000000000000");
      await mockToken.transfer(router.address, "100000000000000000000");

      // await mockToken.approve(lpStaking.address, "10000000000000000000");

      // await lpStaking.deposit(0, "10000000000000000000");

      const period = 864000; // 10 days
      await network.provider.send("evm_increaseTime", [period]);
      await network.provider.send("evm_mine"); // this one will have 02:00 PM as its timestamp

      // await lpStaking.updatePool(0); // pid: 0
      const poolInfo = await lpStaking.poolInfo(0);
      console.log(`poolInfo: ${poolInfo}`);
      await boostContract.autoCompound(mockToken.address);
      let userInfo = await lpStaking.userInfo(0, boostContract.address);
      console.log(`userInfo: ${userInfo}`);
      const lpBalance = await lpStaking.lpBalances(0);
      console.log(`lp balance: ${lpBalance}`);

      // const stgAmount = await stargateToken.balanceOf(boostContract.address);
      // console.log(`stgAmount: ${stgAmount}`);
      userInfo = await boostContract.userInfo(owner.address, 0);
      const currentDeposit = userInfo.amount;
      console.log(`currentDeposit: ${currentDeposit}`);
      expect(currentDeposit).to.equal("10003996003990000000");
    });

    it("Add USDC and WETH successfully", async () => {
      await lpStaking.add(allocPoint, mockToken.address);
      await mockToken.approve(boostContract.address, "10000000000000000000");
      // await boostContract.deposit(mockToken.address, "10000000000000000000");
      await stargateToken.transfer(lpStaking.address, "100000000000000000000");
      await mockToken.transfer(router.address, "100000000000000000000");

      await lpStaking.add(allocPoint, weth.address);
      await boostContract.setPid(weth.address, 1);

      const usdPid = await boostContract.addressToPid(mockToken.address);
      const wethPid = await boostContract.addressToPid(weth.address);

      expect(usdPid).to.equal("0");
      expect(wethPid).to.equal("1");
    });

    it("Deposit ETH successfully", async () => {
      await lpStaking.add(allocPoint, mockToken.address);
      await mockToken.approve(boostContract.address, "10000000000000000000");
      // await boostContract.deposit(mockToken.address, "10000000000000000000");
      await stargateToken.transfer(lpStaking.address, "100000000000000000000");
      await mockToken.transfer(router.address, "100000000000000000000");

      await lpStaking.add(allocPoint, weth.address);
      await boostContract.setPid(weth.address, 1);

      const usdPid = await boostContract.addressToPid(mockToken.address);
      const wethPid = await boostContract.addressToPid(weth.address);

      await boostContract.deposit(weth.address, "10000000000000000000", {
        value: "10000000000000000000",
      });
      const userInfo = await boostContract.userInfo(owner.address, "1");
      const ethDepositAmount = userInfo.amount.toString();
      expect(ethDepositAmount).to.equal("10000000000000000000");
    });

    it("Withdraw ETH successfully", async () => {
      const standardAmount = "10000000000000000000";
      await lpStaking.add(allocPoint, mockToken.address);
      await mockToken.approve(boostContract.address, standardAmount);
      // await boostContract.deposit(mockToken.address, "10000000000000000000");
      await stargateToken.transfer(lpStaking.address, standardAmount);
      await mockToken.transfer(router.address, standardAmount);

      await lpStaking.add(allocPoint, weth.address);
      await boostContract.setPid(weth.address, 1);

      const usdPid = await boostContract.addressToPid(mockToken.address);
      const wethPid = await boostContract.addressToPid(weth.address);

      await boostContract.deposit(weth.address, standardAmount, {
        value: standardAmount,
      });

      await boostContract.withdraw(weth.address, standardAmount);

      const userInfo = await boostContract.userInfo(owner.address, "1");
      const ethDepositAmount = userInfo.amount.toString();
      expect(ethDepositAmount).to.equal("0");
    });
  });
});

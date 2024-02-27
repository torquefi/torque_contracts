const {
    time,
    loadFixture,
  } = require("@nomicfoundation/hardhat-toolbox/network-helpers");
  const { expect } = require("chai");
  const { ethers } = require("hardhat");
  const uniswapABI = require('./uniswap.json');
  
  let owner;
  let otherAccount;
  
  let tusdContract;
  let engineContract;
  let tusdAddress;
  let rewardContract;
  
  describe("RewardsUtil", function () {
    
    // We define a fixture to reuse the same setup in every test.
    // We use loadFixture to run this setup once, snapshot that state,
    // and reset Hardhat Network to that snapshot in every test.
    async function deployRewardContract() {
      // Contracts are deployed using the first signer/account by default
      [owner, otherAccount] = await ethers.getSigners();
      console.log("OWNER ADDRESS", owner.address);
      const RewardContract = await ethers.getContractFactory("RewardUtil");
      const rewardContract = await RewardContract.deploy("0xb56C29413AF8778977093B9B4947efEeA7136C36", "0xb56C29413AF8778977093B9B4947efEeA7136C36");
      return rewardContract;
    }
  
    describe("Deploy Reward Contract", function () {
        it("Should deploy Reward", async function () {
            rewardContract = await loadFixture(deployRewardContract);
            expect(await rewardContract.owner()).to.equal(owner.address);
        });

        it("Should check userDepositReward Unauthorized", async function () {
            const _amount = await ethers.parseUnits('10', 10);
            await expect(rewardContract.userDepositReward("0x70997970C51812dc3A010C7d01b50e0d17dc79C8",_amount)).to.be.revertedWith("Unauthorised!");
        });

        it("Should authorize contract", async function () {
            const _amount = await ethers.parseUnits('10', 10);
            await rewardContract.addTorqueContract(owner,_amount,_amount,0);
            expect(await rewardContract.isTorqueContract(owner)).to.equal(true);
        });

        it("Should get Reward Config ", async function () {
            console.log(await rewardContract.getRewardConfig(owner, "0x70997970C51812dc3A010C7d01b50e0d17dc79C8"));
        });

        it("Should set userDepositReward ", async function () {
            const _amount = await ethers.parseUnits('10', 10);
            await rewardContract.userDepositReward("0x70997970C51812dc3A010C7d01b50e0d17dc79C8",_amount);
        });
    
        it("Should get Reward Config ", async function () {
            console.log(await rewardContract.getRewardConfig(owner, "0x70997970C51812dc3A010C7d01b50e0d17dc79C8"));
        });

        it("Should update rewards ", async function() {
            for(let i = 0; i < 10; i++) {
                await ethers.provider.send("evm_mine", []);
            }
            await rewardContract.updateReward(owner, "0x70997970C51812dc3A010C7d01b50e0d17dc79C8");
            console.log(await rewardContract.getRewardConfig(owner, "0x70997970C51812dc3A010C7d01b50e0d17dc79C8"));
        })
        
        it("Should do Withdraw ", async function () {
            const _amount = await ethers.parseUnits('10', 10);
            await rewardContract.userWithdrawReward("0x70997970C51812dc3A010C7d01b50e0d17dc79C8",_amount);
        });

        it("Should get Reward Config ", async function () {
            console.log(await rewardContract.getRewardConfig(owner, "0x70997970C51812dc3A010C7d01b50e0d17dc79C8"));
        });

        it("Should set userDepositReward ", async function () {
            const _amount = await ethers.parseUnits('10', 5);
            await rewardContract.userDepositReward("0x70997970C51812dc3A010C7d01b50e0d17dc79C8",_amount);
            console.log(await rewardContract.getRewardConfig(owner, "0x70997970C51812dc3A010C7d01b50e0d17dc79C8"));
        });

        it("Should update rewards ", async function() {
            for(let i = 0; i < 10; i++) {
                await ethers.provider.send("evm_mine", []);
            }
            await rewardContract.updateReward(owner, "0x70997970C51812dc3A010C7d01b50e0d17dc79C8");
            console.log(await rewardContract.getRewardConfig(owner, "0x70997970C51812dc3A010C7d01b50e0d17dc79C8"));
        })

        it("Should add userDepositReward ", async function () {
            const _amount = await ethers.parseUnits('10', 5);
            await rewardContract.userDepositReward("0x70997970C51812dc3A010C7d01b50e0d17dc79C8",_amount);
            console.log(await rewardContract.getRewardConfig(owner, "0x70997970C51812dc3A010C7d01b50e0d17dc79C8"));
        });

        // it("Should do mid claim ", async function () {
        //     await rewardContract.connect(otherAccount).claimReward(owner);
        //     console.log(await rewardContract.getRewardConfig(owner, "0x70997970C51812dc3A010C7d01b50e0d17dc79C8"));
        // });

        it("Should update rewards ", async function() {
            for(let i = 0; i < 10; i++) {
                await ethers.provider.send("evm_mine", []);
            }
            await rewardContract.updateReward(owner, "0x70997970C51812dc3A010C7d01b50e0d17dc79C8");
            console.log(await rewardContract.getRewardConfig(owner, "0x70997970C51812dc3A010C7d01b50e0d17dc79C8"));
        })

        it("Should do Withdraw ", async function () {
            const _amount = await ethers.parseUnits('20', 5);
            await rewardContract.userWithdrawReward("0x70997970C51812dc3A010C7d01b50e0d17dc79C8",_amount);
            console.log(await rewardContract.getRewardConfig(owner, "0x70997970C51812dc3A010C7d01b50e0d17dc79C8"));
        });

        // it("Should do claim ", async function () {
        //     await rewardContract.connect(otherAccount).claimReward(owner);
        //     console.log(await rewardContract.getRewardConfig(owner, "0x70997970C51812dc3A010C7d01b50e0d17dc79C8"));
        // });

    });

    describe("Deploy Reward Contract with Borrow", function () {
        it("Should deploy Reward", async function () {
            rewardContract = await loadFixture(deployRewardContract);
            expect(await rewardContract.owner()).to.equal(owner.address);
        });

        it("Should check userDepositReward Unauthorized", async function () {
            const _amount = await ethers.parseUnits('10', 10);
            await expect(rewardContract.userDepositReward("0x70997970C51812dc3A010C7d01b50e0d17dc79C8",_amount)).to.be.revertedWith("Unauthorised!");
        });

        it("Should authorize contract", async function () {
            const _amount = await ethers.parseUnits('10', 10);
            const _amountBorrow = await ethers.parseUnits('50', 7);
            await rewardContract.addTorqueContract(owner,_amount,_amount,_amountBorrow);
            expect(await rewardContract.isTorqueContract(owner)).to.equal(true);
        });

        it("Should get Reward Config ", async function () {
            console.log(await rewardContract.getRewardConfig(owner, "0x70997970C51812dc3A010C7d01b50e0d17dc79C8"));
        });

        it("Should set userDepositReward ", async function () {
            const _amount = await ethers.parseUnits('10', 10);
            const _amountBorrow = await ethers.parseUnits('20', 5);
            await rewardContract.userDepositReward("0x70997970C51812dc3A010C7d01b50e0d17dc79C8",_amount);
            console.log(await rewardContract.getRewardConfig(owner, "0x70997970C51812dc3A010C7d01b50e0d17dc79C8"));
            await rewardContract.userDepositBorrowReward("0x70997970C51812dc3A010C7d01b50e0d17dc79C8",_amountBorrow);
        });
    
        it("Should get Reward Config ", async function () {
            console.log(await rewardContract.getRewardConfig(owner, "0x70997970C51812dc3A010C7d01b50e0d17dc79C8"));
        });

        it("Should update rewards ", async function() {
            for(let i = 0; i < 10; i++) {
                await ethers.provider.send("evm_mine", []);
            }
            await rewardContract.updateReward(owner, "0x70997970C51812dc3A010C7d01b50e0d17dc79C8");
            console.log(await rewardContract.getRewardConfig(owner, "0x70997970C51812dc3A010C7d01b50e0d17dc79C8"));
        })
        
        it("Should do Withdraw ", async function () {
            const _amount = await ethers.parseUnits('10', 10);
            const _amountBorrow = await ethers.parseUnits('20', 5);
            await rewardContract.userWithdrawReward("0x70997970C51812dc3A010C7d01b50e0d17dc79C8",_amount);
            await rewardContract.userWithdrawBorrowReward("0x70997970C51812dc3A010C7d01b50e0d17dc79C8", _amountBorrow)
        });

        it("Should get Reward Config ", async function () {
            console.log(await rewardContract.getRewardConfig(owner, "0x70997970C51812dc3A010C7d01b50e0d17dc79C8"));
        });

        it("Should set userDepositReward ", async function () {
            const _amount = await ethers.parseUnits('10', 5);
            await rewardContract.userDepositReward("0x70997970C51812dc3A010C7d01b50e0d17dc79C8",_amount);
            console.log(await rewardContract.getRewardConfig(owner, "0x70997970C51812dc3A010C7d01b50e0d17dc79C8"));
        });

        it("Should update rewards ", async function() {
            for(let i = 0; i < 10; i++) {
                await ethers.provider.send("evm_mine", []);
            }
            await rewardContract.updateReward(owner, "0x70997970C51812dc3A010C7d01b50e0d17dc79C8");
            console.log(await rewardContract.getRewardConfig(owner, "0x70997970C51812dc3A010C7d01b50e0d17dc79C8"));
        })

        it("Should add userDepositReward ", async function () {
            const _amount = await ethers.parseUnits('10', 5);
            await rewardContract.userDepositReward("0x70997970C51812dc3A010C7d01b50e0d17dc79C8",_amount);
            console.log(await rewardContract.getRewardConfig(owner, "0x70997970C51812dc3A010C7d01b50e0d17dc79C8"));
        });

        // it("Should do mid claim ", async function () {
        //     await rewardContract.connect(otherAccount).claimReward(owner);
        //     console.log(await rewardContract.getRewardConfig(owner, "0x70997970C51812dc3A010C7d01b50e0d17dc79C8"));
        // });

        it("Should update rewards ", async function() {
            for(let i = 0; i < 10; i++) {
                await ethers.provider.send("evm_mine", []);
            }
            await rewardContract.updateReward(owner, "0x70997970C51812dc3A010C7d01b50e0d17dc79C8");
            console.log(await rewardContract.getRewardConfig(owner, "0x70997970C51812dc3A010C7d01b50e0d17dc79C8"));
        })

        it("Should do Withdraw ", async function () {
            const _amount = await ethers.parseUnits('20', 5);
            await rewardContract.userWithdrawReward("0x70997970C51812dc3A010C7d01b50e0d17dc79C8",_amount);
            console.log(await rewardContract.getRewardConfig(owner, "0x70997970C51812dc3A010C7d01b50e0d17dc79C8"));
        });

        // it("Should do claim ", async function () {
        //     await rewardContract.connect(otherAccount).claimReward(owner);
        //     console.log(await rewardContract.getRewardConfig(owner, "0x70997970C51812dc3A010C7d01b50e0d17dc79C8"));
        // });

    });

  });
  
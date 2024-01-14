const {
  time,
  loadFixture,
} = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const { expect } = require("chai");
const { ethers } = require("hardhat");

let owner;
let otherAccount;
describe("BTCBorrow", function () {
  // We define a fixture to reuse the same setup in every test.
  // We use loadFixture to run this setup once, snapshot that state,
  // and reset Hardhat Network to that snapshot in every test.
  async function deployBorrowBTCContract() {
    // Contracts are deployed using the first signer/account by default
    [owner, otherAccount] = await ethers.getSigners();
    console.log("OWNER ADDRESS", owner.address);
    const BTCBorrow = await ethers.getContractFactory("BTCBorrow");
    const btcBorrow = await BTCBorrow.deploy(owner.address, 
    "0x9c4ec768c28520b50860ea7a15bd7213a9ff58bf", 
    "0x88730d254A2f7e6AC8388c3198aFd694bA9f7fae", 
    "0x2f2a2543b76a4166549f7aab2e75bef0aefc5b0f",
    "0xaf88d065e77c8cC2239327C5EDb3A432268e5831",
    "0xbdE8F31D2DdDA895264e27DD990faB3DC87b372d",
    "0x82536a410d4762d67bff6de0e95f15bc80e052e9",
    "0xa0985c4e6f2a1e694f58b93df3e5f4ba8a09b239",
    "0x0f773B3d518d0885DbF0ae304D87a718F68EEED5",
    1);
    console.log("BTC Borrow Contract Address", btcBorrow.address);
    return btcBorrow;
  }

  describe("Deployment", function () {
    let btcBorrow;
    it("Should deploy", async function () {
      btcBorrow = await loadFixture(deployBorrowBTCContract);
      expect(await btcBorrow.owner()).to.equal(owner.address);
    });

    it("Should get 98% of USDC values", async function () {
      expect(await btcBorrow.getMintableToken(owner,1000000000)).to.equal(1000000000*98/100);
    });

    it("Should get 100% of USDC values when burning", async function () {
      await expect(btcBorrow.getBurnableToken(owner.address, 980000000)).to.be.revertedWith("You have not minted enough TUSD");
    });

    it("Should get borrowable usdc", async function () {
      console.log("TEST Borrowable USDC", await btcBorrow.getBorrowableUsdc(100000000))
      expect(await btcBorrow.getBorrowableUsdc(100000000)).to.not.equal(0);
    });

    it("Should get collateral factor from coment", async function() {
      console.log("TEST Collateral Factor ", await btcBorrow.getCollateralFactor());
      expect(await btcBorrow.getCollateralFactor()).to.not.equal(0);
    })

    it("Should get error when checking for borrow", async function() {
      expect(await btcBorrow.getUserBorrowable(owner.address)).to.equal(0);
    })
    
    it("Should get error when withdrawing funds without supply", async function() {
      await expect(btcBorrow.withdraw(1)).to.be.revertedWith("User does not have asset");
    })

    // it("Should fail if the unlockTime is not in the future", async function () {
    //   // We don't use the fixture here because we want a different deployment
    //   const latestTime = await time.latest();
    //   const Lock = await ethers.getContractFactory("Lock");
    //   await expect(Lock.deploy(latestTime, { value: 1 })).to.be.revertedWith(
    //     "Unlock time should be in the future"
    //   );
    // });
  });

  `describe("Withdrawals", function () {
    describe("Validations", function () {
      it("Should revert with the right error if called too soon", async function () {
        const { lock } = await loadFixture(deployOneYearLockFixture);

        await expect(lock.withdraw()).to.be.revertedWith(
          "You can't withdraw yet"
        );
      });

      it("Should revert with the right error if called from another account", async function () {
        const { lock, unlockTime, otherAccount } = await loadFixture(
          deployOneYearLockFixture
        );

        // We can increase the time in Hardhat Network
        await time.increaseTo(unlockTime);

        // We use lock.connect() to send a transaction from another account
        await expect(lock.connect(otherAccount).withdraw()).to.be.revertedWith(
          "You aren't the owner"
        );
      });

      it("Shouldn't fail if the unlockTime has arrived and the owner calls it", async function () {
        const { lock, unlockTime } = await loadFixture(
          deployOneYearLockFixture
        );

        // Transactions are sent using the first signer by default
        await time.increaseTo(unlockTime);

        await expect(lock.withdraw()).not.to.be.reverted;
      });
    });

    describe("Events", function () {
      it("Should emit an event on withdrawals", async function () {
        const { lock, unlockTime, lockedAmount } = await loadFixture(
          deployOneYearLockFixture
        );

        await time.increaseTo(unlockTime);

        await expect(lock.withdraw())
          .to.emit(lock, "Withdrawal")
          .withArgs(lockedAmount, anyValue); // We accept any value as when arg
      });
    });

    describe("Transfers", function () {
      it("Should transfer the funds to the owner", async function () {
        const { lock, unlockTime, lockedAmount, owner } = await loadFixture(
          deployOneYearLockFixture
        );

        await time.increaseTo(unlockTime);

        await expect(lock.withdraw()).to.changeEtherBalances(
          [owner, lock],
          [lockedAmount, -lockedAmount]
        );
      });
    });
  });`
});

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
    
    it("Should borrow TUSD for supply of 1WBTC ", async function() {
      try{
        const uniswapRouter = new ethers.Contract(uniswapRouterAddress, ['function swapExactETHForTokens(uint amountOutMin, address[] calldata path, address to, uint deadline) payable returns (uint[] memory amounts)'], owner);
        const amountOutMin = 1;
        const path = ["0x82aF49447D8a07e3bd95BD0d56f35241523fBab1", wbtcAddress];
        const to = owner.address;
        const deadline = Math.floor(Date.now() / 1000) + 60000;
        const weiValue = await ethers.parseUnits('10', 18);
        const result = await uniswapRouter.swapExactETHForTokens(amountOutMin, path, to, deadline, {value: weiValue});
        console.log("Swap Result: ", result);
        console.log("TEST ", deadline);
      }
      catch (error) {
        console.error("Error:", error.message || error.reason || error.toString());
      }
    })
  })
});

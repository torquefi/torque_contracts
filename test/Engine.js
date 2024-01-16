const {
  time,
  loadFixture,
} = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const { expect } = require("chai");
const { ethers } = require("hardhat");
const uniswapABI = require('./uniswap.json');

let owner;
let otherAccount;

const uniswapRouterAddress = "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D";
const wbtcAddress = "0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f"; 

describe("EngineContract", function () {
  
  // We define a fixture to reuse the same setup in every test.
  // We use loadFixture to run this setup once, snapshot that state,
  // and reset Hardhat Network to that snapshot in every test.
  async function deployEngineContract() {
    // Contracts are deployed using the first signer/account by default
    [owner, otherAccount] = await ethers.getSigners();
    console.log("OWNER ADDRESS", owner.address);
    const EngineContract = await ethers.getContractFactory("TUSDEngine");
    const engineContract = await EngineContract.deploy("0xaf88d065e77c8cC2239327C5EDb3A432268e5831",
    "0x50834f3163758fcc1df9973b6e91f0f0f0434ad3");
    return engineContract;
  }

  describe("Engine Contract", function () {
    let engineContract;
    it("Should deploy", async function () {
      engineContract = await loadFixture(deployEngineContract);
      expect(await engineContract.owner()).to.equal(owner.address);
    });
    it("Should check _calculateHealthFactor 4000, 4082", async function () {
      console.log(await engineContract._calculateHealthFactor(40,42));
    });
    it("Should check 4082, 4000", async function () {
      console.log(await engineContract.depositCollateralAndMintTusd(41,40));
    });
    
    it("Should check 4081 USD", async function () {
      console.log(await engineContract.getUsdValue(42));
    });
  });
});
//1000000000000000000
import {
    time,
    loadFixture,
  } from "@nomicfoundation/hardhat-toolbox/network-helpers";
  import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";
  import { expect } from "chai";
  import { ethers } from "hardhat";
  
  describe("# Tokenized USD by Torque Inc.", function () {
    // We define a fixture to reuse the same setup in every test.
    // We use loadFixture to run this setup once, snapshot that state,
    // and reset Hardhat Network to that snapshot in every test.
    async function initialize() {
      // Contracts are deployed using the first signer/account by default
      const [deployer, alice, bob, daniel, signer] = await ethers.getSigners();
  
      const usd = await ethers.deployContract("USD", []);
  
      const usdcTest = await ethers.deployContract("USDCTest", []);
  
      const wethTest = await ethers.deployContract("USDCTest", []);
  
      const aggregatorUSDC = await ethers.deployContract(
        "AggregatorUSDCTest",
        []
      );
  
      const aggregatorWETH = await ethers.deployContract(
        "AggregatorUSDCTest",
        []
      );
  
      const usdEngine = await ethers.deployContract("USDEngine", [
        [usdcTest.target, wethTest.target],
        [aggregatorUSDC.target, aggregatorWETH.target],
        [50, 50],
        usd.target,
      ]);
  
      await usd.transferOwnership(usdEngine.target);
      const newWETHPrice = "180000000000"; // 1 ETH approximately equal 1800 USD
      await aggregatorWETH.updatePrice(newWETHPrice);
      await usdEngine.updateWETH(wethTest.target);
  
      return {
        deployer,
        alice,
        bob,
        daniel,
        signer,
        usd,
        usdcTest,
        wethTest,
        aggregatorUSDC,
        aggregatorWETH,
        usdEngine,
      };
    }
  
    describe("Test USD Basic cases", function () {
      it("[1]: Mint USD - success case", async function () {
        const {
          deployer,
          alice,
          bob,
          daniel,
          signer,
          usd,
          usdcTest,
          aggregatorUSDC,
          usdEngine,
        } = await loadFixture(initialize);
  
        const usdcAmount = ethers.parseEther("1000");
        const usdAmount = ethers.parseEther("500");
        await usdcTest.approve(usdEngine.target, usdcAmount);
        await usdEngine.depositCollateralAndMintUsd(
          usdcTest.target,
          usdcAmount,
          usdAmount
        );
  
        const usdDeployerBalance = await usd.balanceOf(deployer.address);
        expect(usdDeployerBalance).to.equal(usdAmount);
      });
  
      it("[2]: Burn USD - success case", async function () {
        const {
          deployer,
          alice,
          bob,
          daniel,
          signer,
          usd,
          usdcTest,
          aggregatorUSDC,
          usdEngine,
        } = await loadFixture(initialize);
  
        const usdcAmount = ethers.parseEther("1000");
        const usdAmount = ethers.parseEther("500");
        await usdcTest.approve(usdEngine.target, usdcAmount);
        await usdEngine.depositCollateralAndMintUsd(
          usdcTest.target,
          usdcAmount,
          usdAmount
        );
  
        await usd.approve(usdEngine.target, usdAmount);
        await usdEngine.redeemCollateralForUsd(
          usdcTest.target,
          usdcAmount,
          usdAmount
        );
  
        const usdDeployerBalance = await usd.balanceOf(deployer.address);
        expect(usdDeployerBalance).to.equal("0");
        const usdcDeployerBalance = await usdcTest.balanceOf(deployer.address);
        const usdcDeployerBalanceInitial = ethers.parseEther("1000000");
        expect(usdcDeployerBalance).to.equal(usdcDeployerBalanceInitial);
      });
  
      it("[3]: Mint USD - fail case due to over collateral mint", async function () {
        const {
          deployer,
          alice,
          bob,
          daniel,
          signer,
          usd,
          usdcTest,
          aggregatorUSDC,
          usdEngine,
        } = await loadFixture(initialize);
  
        const usdcAmount = ethers.parseEther("1000");
        const usdAmount = ethers.parseEther("501");
        await usdcTest.approve(usdEngine.target, usdcAmount);
        const mintFunc = usdEngine.depositCollateralAndMintUsd(
          usdcTest.target,
          usdcAmount,
          usdAmount
        );
  
        await expect(mintFunc)
          .to.be.revertedWithCustomError(
            usdEngine,
            "USDEngine__BreaksHealthFactor"
          )
          .withArgs("998003992015968063");
      });
  
      it("[4]: Burn USD - failed case due to burn over collateral USD asset", async function () {
        const {
          deployer,
          alice,
          bob,
          daniel,
          signer,
          usd,
          usdcTest,
          aggregatorUSDC,
          usdEngine,
        } = await loadFixture(initialize);
  
        const usdcAmount = ethers.parseEther("1000");
        const mintUsdAmount = ethers.parseEther("500");
        const burnUsdAmount = ethers.parseEther("499");
        await usdcTest.approve(usdEngine.target, usdcAmount);
        await usdEngine.depositCollateralAndMintUsd(
          usdcTest.target,
          usdcAmount,
          mintUsdAmount
        );
  
        await usd.approve(usdEngine.target, burnUsdAmount);
        const burnFunc = usdEngine.redeemCollateralForUsd(
          usdcTest.target,
          usdcAmount,
          burnUsdAmount
        );
  
        await expect(burnFunc)
          .to.revertedWithCustomError(usdEngine, "USDEngine__BreaksHealthFactor")
          .withArgs("0");
  
        const usdDeployerBalance = await usd.balanceOf(deployer.address);
        expect(usdDeployerBalance).to.equal(mintUsdAmount);
        const usdcDeployerBalance = await usdcTest.balanceOf(deployer.address);
        const usdcDeployerBalanceAfterMintUsd = ethers.parseEther("999000");
        const usdcDeployerBalanceInitial = ethers.parseEther("1000000");
        expect(usdcDeployerBalance).to.equal(usdcDeployerBalanceAfterMintUsd);
      });
    });
  
    describe("Test USD when collateral price fluctuate", () => {
      it("[5]: Cannot mint USD when price of collateral is decrease by 50 % - fail case", async function () {
        const {
          deployer,
          alice,
          bob,
          daniel,
          signer,
          usd,
          usdcTest,
          aggregatorUSDC,
          usdEngine,
        } = await loadFixture(initialize);
  
        const usdcAmount = ethers.parseEther("1000");
        const usdAmount = ethers.parseEther("500");
        await usdcTest.approve(usdEngine.target, usdcAmount);
        await usdEngine.depositCollateralAndMintUsd(
          usdcTest.target,
          usdcAmount,
          usdAmount
        );
  
        const usdDeployerBalance = await usd.balanceOf(deployer.address);
        expect(usdDeployerBalance).to.equal(usdAmount);
  
        const newUsdcPrice = "50000000";
        await aggregatorUSDC.updatePrice(newUsdcPrice);
  
        const mintUsdFunc = usdEngine.mintUsd("1");
        await expect(mintUsdFunc)
          .to.be.revertedWithCustomError(
            usdEngine,
            "USDEngine__BreaksHealthFactor"
          )
          .withArgs("499999999999999999");
      });
  
      it("[6]: Cannot mint USD when burn USD to the point of critical health factor where collateral token price decrease by 50% - fail case", async () => {
        const {
          deployer,
          alice,
          bob,
          daniel,
          signer,
          usd,
          usdcTest,
          aggregatorUSDC,
          usdEngine,
        } = await loadFixture(initialize);
  
        const usdcAmount = ethers.parseEther("1000");
        const usdAmount = ethers.parseEther("500");
        const burnUsdAmount = ethers.parseEther("250");
        await usdcTest.approve(usdEngine.target, usdcAmount);
        await usdEngine.depositCollateralAndMintUsd(
          usdcTest.target,
          usdcAmount,
          usdAmount
        );
  
        const usdDeployerBalance = await usd.balanceOf(deployer.address);
        expect(usdDeployerBalance).to.equal(usdAmount);
  
        const newUsdcPrice = "50000000";
        await aggregatorUSDC.updatePrice(newUsdcPrice);
  
        await usd.approve(usdEngine, burnUsdAmount);
        await usdEngine.burnUsd(burnUsdAmount);
  
        const mintUsdFunc = usdEngine.mintUsd("1");
        await expect(mintUsdFunc)
          .to.be.revertedWithCustomError(
            usdEngine,
            "USDEngine__BreaksHealthFactor"
          )
          .withArgs("999999999999999999");
      });
  
      it("[7]: Can mint USD if enough health factor when collateral token price decrease by 50% - success case", async () => {
        const {
          deployer,
          alice,
          bob,
          daniel,
          signer,
          usd,
          usdcTest,
          aggregatorUSDC,
          usdEngine,
        } = await loadFixture(initialize);
  
        const usdcAmount = ethers.parseEther("1000");
        const usdAmount = ethers.parseEther("500");
        const burnUsdAmount = ethers.parseEther("251");
        const mintUsdAmount = ethers.parseEther("1");
        await usdcTest.approve(usdEngine.target, usdcAmount);
        await usdEngine.depositCollateralAndMintUsd(
          usdcTest.target,
          usdcAmount,
          usdAmount
        );
  
        const usdDeployerBalance = await usd.balanceOf(deployer.address);
        expect(usdDeployerBalance).to.equal(usdAmount);
  
        const newUsdcPrice = "50000000";
        await aggregatorUSDC.updatePrice(newUsdcPrice);
  
        await usd.approve(usdEngine, burnUsdAmount);
        await usdEngine.burnUsd(burnUsdAmount);
  
        await usdEngine.mintUsd(mintUsdAmount);
  
        const deployerUsdBalance = await usd.balanceOf(deployer.address);
        const finalDeployerUsdBalance = ethers.parseEther("250");
        expect(deployerUsdBalance).to.equal(finalDeployerUsdABalance);
      });
  
      it("[8]: Can mint USD when price of collateral is increase by 100 % - success case", async function () {
        const {
          deployer,
          alice,
          bob,
          daniel,
          signer,
          usd,
          usdcTest,
          aggregatorUSDC,
          usdEngine,
        } = await loadFixture(initialize);
  
        const usdcAmount = ethers.parseEther("1000");
        const usdAmount = ethers.parseEther("500");
        const mintUsdAmount = ethers.parseEther("500");
        await usdcTest.approve(usdEngine.target, usdcAmount);
        await usdEngine.depositCollateralAndMintUsd(
          usdcTest.target,
          usdcAmount,
          usdAmount
        );
  
        const usdDeployerBalance = await usd.balanceOf(deployer.address);
        expect(usdDeployerBalance).to.equal(usdAmount);
  
        const newUsdcPrice = "200000000";
        await aggregatorUSDC.updatePrice(newUsdcPrice);
  
        await usdEngine.mintUsd(mintUsdAmount);
        const finalUsdDeployerBalance = await usd.balanceOf(deployer.address);
        expect(finalUsdDeployerBalance).to.equal(usdcAmount); // double balance
      });
    });
  
    describe("Test USD with suspicious token collateral", () => {
      it("[9]: Alice have to burn all the suspicious usd token to get back collateral - success case", async function () {
        const {
          deployer,
          alice,
          bob,
          daniel,
          signer,
          usd,
          usdcTest,
          aggregatorUSDC,
          usdEngine,
        } = await loadFixture(initialize);
  
        // deployer transfer usdc to alice
        const usdcToAlice = ethers.parseEther("500000");
        await usdcTest.transfer(alice.address, usdcToAlice);
  
        // alice supply collateral to mint USD
        const usdcAmount = ethers.parseEther("1000");
        const usdAmount = ethers.parseEther("500");
        await usdcTest.connect(alice).approve(usdEngine.target, usdcAmount);
        await usdEngine
          .connect(alice)
          .depositCollateralAndMintUsd(usdcTest.target, usdcAmount, usdAmount);
  
        const usdAliceBalance = await usd.balanceOf(alice.address);
        expect(usdAliceBalance).to.equal(usdAmount);
  
        const newUsdcPrice = "0"; // deployer withdraw all pool of usdc pair liquidity - SUSPECT !!!
        await aggregatorUSDC.updatePrice(newUsdcPrice);
  
        // alice has to burn all the usd token before get back collateral
        await usd.connect(alice).approve(usdEngine.target, usdAliceBalance);
        await usdEngine
          .connect(alice)
          .redeemCollateralForUsd(usdcTest.target, usdcAmount, usdAliceBalance);
  
        // alice can get back the collateral but it is unvaluable
        // The problem here is to choose the reliable asset for usd's collateral
      });
    });
  
    describe("Get current usd mintable amount for UI", () => {
      it("[10]: Get usd mintable amount - success case", async () => {
        const {
          deployer,
          alice,
          bob,
          daniel,
          signer,
          usd,
          usdcTest,
          aggregatorUSDC,
          usdEngine,
        } = await loadFixture(initialize);
  
        const usdcAmount = ethers.parseEther("1000");
        const usdAmount = ethers.parseEther("500");
        const [mintableUsdAMount, mintable] = await usdEngine.getMintableUSD(
          usdcTest.target,
          deployer.address,
          usdcAmount
        );
  
        expect(mintableUsdAMount).to.equal(usdAmount);
        expect(mintable).to.equal(true);
      });
  
      it("[11]: Get usd mintable amount when already minted a certain usd amount - success case", async () => {
        const {
          deployer,
          alice,
          bob,
          daniel,
          signer,
          usd,
          usdcTest,
          aggregatorUSDC,
          usdEngine,
        } = await loadFixture(initialize);
  
        const usdcAmount = ethers.parseEther("1000");
        const usdAmount = ethers.parseEther("250"); // Predict mint 250 USD, and the remain mintable amount is 250
        await usdcTest.approve(usdEngine.target, usdcAmount);
        await usdEngine.depositCollateralAndMintUsd(
          usdcTest.target,
          usdcAmount,
          usdAmount
        );
  
        const [mintableUsdAMount, mintable] = await usdEngine.getMintableUSD(
          usdcTest.target,
          deployer.address,
          "0"
        );
  
        expect(mintable).to.equal(true);
        expect(mintableUsdAMount).to.equal(usdAmount);
      });
  
      it("[12]: Get the debt usd amount then the collateral decrease by 50% - success case", async () => {
        const {
          deployer,
          alice,
          bob,
          daniel,
          signer,
          usd,
          usdcTest,
          aggregatorUSDC,
          usdEngine,
        } = await loadFixture(initialize);
  
        const usdcAmount = ethers.parseEther("1000");
        const usdAmount = ethers.parseEther("500");
        const predictMintableUsdAMount = ethers.parseEther("250");
        await usdcTest.approve(usdEngine.target, usdcAmount);
        await usdEngine.depositCollateralAndMintUsd(
          usdcTest.target,
          usdcAmount,
          usdAmount
        );
  
        const newPrice = "50000000";
        await aggregatorUSDC.updatePrice(newPrice);
  
        const [mintableUsdAMount, mintable] = await usdEngine.getMintableUSD(
          usdcTest.target,
          deployer.address,
          "0"
        );
  
        expect(mintableUsdAMount).to.equal(predictMintableUsdAMount);
        expect(mintable).to.equal(false);
      });
  
      it("[13]: Get the asset receive when burn usd (normal case) - success case", async () => {
        const {
          deployer,
          alice,
          bob,
          daniel,
          signer,
          usd,
          usdcTest,
          aggregatorUSDC,
          usdEngine,
        } = await loadFixture(initialize);
  
        const usdcAmount = ethers.parseEther("1000");
        const usdAmount = ethers.parseEther("500");
        await usdcTest.approve(usdEngine.target, usdcAmount);
        await usdEngine.depositCollateralAndMintUsd(
          usdcTest.target,
          usdcAmount,
          usdAmount
        );
  
        const assetReceive = await usdEngine.getBurnableUSD(
          usdcTest.target,
          deployer.address,
          usdAmount
        );
  
        expect(assetReceive).to.equal(usdcAmount);
      });
  
      it("[14]: Get the asset receive when burn usd not enough - success case", async () => {
        const {
          deployer,
          alice,
          bob,
          daniel,
          signer,
          usd,
          usdcTest,
          aggregatorUSDC,
          usdEngine,
        } = await loadFixture(initialize);
  
        const usdcAmount = ethers.parseEther("1000");
        const usdAmount = ethers.parseEther("500");
        const usdBurnAmount = ethers.parseEther("200");
        await usdcTest.approve(usdEngine.target, usdcAmount);
        await usdEngine.depositCollateralAndMintUsd(
          usdcTest.target,
          usdcAmount,
          usdAmount
        );
  
        const newPrice = "50000000";
        await aggregatorUSDC.updatePrice(newPrice); // Need to burn at least 250 USD
  
        const assetReceive = await usdEngine.getBurnableUSD(
          usdcTest.target,
          deployer.address,
          usdBurnAmount
        );
  
        expect(assetReceive).to.equal("0");
      });
    });
  
    describe("Test USD with Native token", () => {
      it("[15]: Can mint usd with native token collateral - success case", async () => {
        const {
          deployer,
          alice,
          bob,
          daniel,
          signer,
          usd,
          usdcTest,
          wethTest,
          aggregatorUSDC,
          aggregatorWETH,
          usdEngine,
        } = await loadFixture(initialize);
  
        const wethAmount = ethers.parseEther("1"); // deposit 1 eth to mint 900 usd
        const usdAmount = ethers.parseEther("900");
        await usdEngine.depositCollateralAndMintUsd(
          wethTest.target,
          wethAmount,
          usdAmount,
          { value: wethAmount }
        );
  
        const usdDeployerBalance = await usd.balanceOf(deployer.address);
        expect(usdDeployerBalance).to.equal(usdAmount);
      });
  
      it("[16]: Can burn usd and withdraw native token collateral - success case", async () => {
        const {
          deployer,
          alice,
          bob,
          daniel,
          signer,
          usd,
          usdcTest,
          wethTest,
          aggregatorUSDC,
          aggregatorWETH,
          usdEngine,
        } = await loadFixture(initialize);
  
        const wethAmount = ethers.parseEther("1"); // deposit 1 eth to mint 900 usd
        const usdAmount = ethers.parseEther("900");
        await usdEngine.depositCollateralAndMintUsd(
          wethTest.target,
          wethAmount,
          usdAmount,
          { value: wethAmount }
        );
  
        await usd.approve(usdEngine.target, usdAmount);
        await usdEngine.redeemCollateralForUsd(
          wethTest.target,
          wethAmount,
          usdAmount
        );
  
        const usdDeployerBalance = await usd.balanceOf(deployer.address);
        expect(usdDeployerBalance).to.equal("0");
      });
    });
  
    describe("Test util for update all feeds", () => {
      it("[17]: Update feed success - success case", async () => {
        const {
          deployer,
          alice,
          bob,
          daniel,
          signer,
          usd,
          usdcTest,
          aggregatorUSDC,
          usdEngine,
        } = await loadFixture(initialize);
  
        await usdEngine.updateAllPriceFeed(
          [usdcTest.target],
          [aggregatorUSDC.target],
          [50]
        );
  
        const collateralTokens = usdEngine.s_collateralTokens(1);
        expect(collateralTokens).to.revertedWith(
          "Transaction reverted and Hardhat couldn't infer the reason." // exceed arrays
        );
      });
    });
  });  
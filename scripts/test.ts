import * as hre from 'hardhat';
import { WaultWbnbVault } from '../types/ethers-contracts/WaultWbnbVault';
import { WaultWbnbVault__factory } from '../types/ethers-contracts/factories/WaultWbnbVault__factory';
import { WaultWbnbVenusStrategy } from '../types/ethers-contracts/WaultWbnbVenusStrategy';
import { WaultWbnbVenusStrategy__factory } from '../types/ethers-contracts/factories/WaultWbnbVenusStrategy__factory';
import { ERC20__factory } from '../types/ethers-contracts/factories/ERC20__factory';
import { assert } from 'sinon';

require("dotenv").config();

const { ethers } = hre;

const sleep = (milliseconds, msg='') => {
    console.log(`Wait ${milliseconds} ms... (${msg})`);
    const date = Date.now();
    let currentDate = null;
    do {
      currentDate = Date.now();
    } while (currentDate - date < milliseconds);
}

const toEther = (val) => {
    return ethers.utils.formatEther(val);
}

const parseEther = (val) => {
    return ethers.utils.parseEther(val);
}

async function deploy() {
    console.log((new Date()).toLocaleString());
    
    const [deployer] = await ethers.getSigners();
    
    console.log(
        "Deploying contracts with the account:",
        deployer.address
    );

    const beforeBalance = await deployer.getBalance();
    console.log("Account balance:", (await deployer.getBalance()).toString());

    const mainnet = process.env.NETWORK == "mainnet" ? true : false;
    const url = mainnet ? process.env.URL_MAIN : process.env.URL_TEST;
    const wbnbAddress = mainnet ? process.env.WBNB_MAIN : process.env.WBNB_TEST
    const vaultAddress = mainnet ? process.env.VAULT_MAIN : process.env.VAULT_TEST
    const strategyAddress = mainnet ? process.env.STRATEGY_MAIN : process.env.STRATEGY_TEST

    const vaultFactory: WaultWbnbVault__factory = new WaultWbnbVault__factory(deployer);
    const vault: WaultWbnbVault = await vaultFactory.attach(vaultAddress).connect(deployer);
    const strategyFactory: WaultWbnbVenusStrategy__factory = new WaultWbnbVenusStrategy__factory(deployer);
    const strategy: WaultWbnbVenusStrategy = await strategyFactory.attach(strategyAddress).connect(deployer);
    console.log(`Deployed Vault... (${vault.address})`);
    console.log(`Deployed Strategy... (${strategy.address})`);

    const erc20Factory = new ERC20__factory(deployer);
    const wbnb = await erc20Factory.attach(wbnbAddress).connect(deployer);
    const block = await ethers.getDefaultProvider(url).getBlockNumber();
    console.log("Block number: ", block);
    const wbnbBalance = await wbnb.balanceOf(strategy.address);
    console.log("wbnbBalance: ", toEther(wbnbBalance));

    console.log("supplyRatePerBlock: ", (await strategy.supplyRatePerBlock()).toString());
    console.log("borrowRatePerBlock: ", (await strategy.borrowRatePerBlock()).toString());
    // console.log("supplyRewardRatePerBlock:", (await strategy.supplyRewardRatePerBlock()).toString());
    // console.log("borrowRewardRatePerBlock:", (await strategy.borrowRewardRatePerBlock()).toString());
    // console.log("currentRewardRate:", (await strategy.currentRewardRate()).toString());
    // console.log("priceOfVenus:", (await strategy.priceOfVenus()).toString());
    
    const totalSupply = await vault.totalSupply();
    console.log("totalSupply: ", toEther(totalSupply));
    const balance = await vault.balance();
    console.log("balance: ", toEther(balance));
    const claimed = balance.sub(totalSupply);
    console.log("claimed: ", toEther(claimed));
    const pricePerShare = await vault.getPricePerFullShare();
    console.log("pricePerShare: ", toEther(pricePerShare));
    // const user = '0xC627D743B1BfF30f853AE218396e6d47a4f34ceA';
    const user = '0x61d7c6572922a1ecff8fce8b88920f7eaaab1dae';
    const balanceOf = await vault.balanceOf(user);
    console.log(`balanceOf: ${toEther(balanceOf)} (${user})`);
    const earned = balanceOf.mul(pricePerShare).sub(balanceOf.mul(parseEther('1'))).div(parseEther('1'));
    console.log("earned: ", toEther(earned));

    const afterBalance = await deployer.getBalance();
    console.log(
        "Test cost:",
         (beforeBalance.sub(afterBalance)).toString()
    );
}

deploy()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    })
import * as hre from 'hardhat';
import { WaultEllipsisVault } from '../types/ethers-contracts/WaultEllipsisVault';
import { WaultEllipsisVault__factory } from '../types/ethers-contracts/factories/WaultEllipsisVault__factory';
import { WaultEllipsisStrategy } from '../types/ethers-contracts/WaultEllipsisStrategy';
import { WaultEllipsisStrategy__factory } from '../types/ethers-contracts/factories/WaultEllipsisStrategy__factory';
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
    const eps3Address = mainnet ? process.env.EPS3_MAIN : process.env.EPS3_TEST
    const epsAddress = mainnet ? process.env.EPS_MAIN : process.env.EPS_TEST
    const wbnbAddress = mainnet ? process.env.WBNB_MAIN : process.env.WBNB_TEST
    const busdAddress = mainnet ? process.env.BUSD_MAIN : process.env.BUSD_TEST
    const vaultAddress = mainnet ? process.env.VAULT_MAIN : process.env.VAULT_TEST
    const strategyAddress = mainnet ? process.env.STRATEGY_MAIN : process.env.STRATEGY_TEST

    const vaultFactory: WaultEllipsisVault__factory = new WaultEllipsisVault__factory(deployer);
    const vault: WaultEllipsisVault = await vaultFactory.attach(vaultAddress).connect(deployer);
    const strategyFactory: WaultEllipsisStrategy__factory = new WaultEllipsisStrategy__factory(deployer);
    const strategy: WaultEllipsisStrategy = await strategyFactory.attach(strategyAddress).connect(deployer);
    console.log(`Deployed Vault... (${vault.address})`);
    console.log(`Deployed Strategy... (${strategy.address})`);

    const erc20Factory = new ERC20__factory(deployer);
    const eps3 = await erc20Factory.attach(eps3Address).connect(deployer);
    const eps = await erc20Factory.attach(epsAddress).connect(deployer);
    const busd = await erc20Factory.attach(busdAddress).connect(deployer);
    const wbnb = await erc20Factory.attach(wbnbAddress).connect(deployer);

    const block = await ethers.getDefaultProvider(url).getBlockNumber();
    console.log("Block number: ", block);
    const busdBalance = await busd.balanceOf(strategy.address);
    console.log("busdBalance: ", toEther(busdBalance));
    const wbnbBalance = await wbnb.balanceOf(strategy.address);
    console.log("wbnbBalance: ", toEther(wbnbBalance));
    const epsBalance = await eps.balanceOf(strategy.address);
    console.log("epsBalance: ", toEther(epsBalance));
    const totalSupply = await vault.totalSupply();
    console.log("totalSupply: ", toEther(totalSupply));
    const balance = await vault.balance();
    console.log("balance: ", toEther(balance));
    const claimed = balance.sub(totalSupply);
    console.log("claimed: ", toEther(claimed));
    const claimable = await strategy.claimableReward();
    console.log("cliamable: ", toEther(claimable));
    const harvestable = await strategy.harvestableReward();
    console.log("harvestable amount: ", harvestable.amount.toString());
    console.log("harvestable penalties: ", harvestable.penalties.toString());
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
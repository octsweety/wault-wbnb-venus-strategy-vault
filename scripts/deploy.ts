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
    const eps3Address = mainnet ? process.env.EPS3_MAIN : process.env.EPS3_TEST
    const vaultAddress = mainnet ? process.env.VAULT_MAIN : process.env.VAULT_TEST
    const strategyAddress = mainnet ? process.env.STRATEGY_MAIN : process.env.STRATEGY_TEST

    const vaultFactory: WaultEllipsisVault__factory = new WaultEllipsisVault__factory(deployer);
    const vault: WaultEllipsisVault = await vaultFactory.deploy(eps3Address, 0);
    const strategyFactory: WaultEllipsisStrategy__factory = new WaultEllipsisStrategy__factory(deployer);
    const strategy: WaultEllipsisStrategy = await strategyFactory.deploy(vault.address);
    // const strategy: WaultEllipsisStrategy = await strategyFactory.deploy(vaultAddress);
    console.log(`Deployed Vault... (${vault.address})`);
    console.log(`Deployed Strategy... (${strategy.address})`);

    console.log("Setting strategy address...");
    await vault.setStrategy(strategy.address);
    // const vault = await vaultFactory.attach(vaultAddress).connect(deployer);
    // await vault.setStrategy(strategyAddress);
    
    const afterBalance = await deployer.getBalance();
    console.log(
        "Deployed cost:",
         (beforeBalance.sub(afterBalance)).toString()
    );
}

deploy()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    })
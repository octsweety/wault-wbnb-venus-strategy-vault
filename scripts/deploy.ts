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
    const wbnbAddress = mainnet ? process.env.WBNB_MAIN : process.env.WBNB_TEST
    const vaultAddress = mainnet ? process.env.VAULT_MAIN : process.env.VAULT_TEST
    const strategyAddress = mainnet ? process.env.STRATEGY_MAIN : process.env.STRATEGY_TEST

    const vaultFactory: WaultWbnbVault__factory = new WaultWbnbVault__factory(deployer);
    let vault: WaultWbnbVault = await vaultFactory.attach(vaultAddress).connect(deployer);
    if ("redeploy" && false) {
        vault = await vaultFactory.deploy(wbnbAddress);
    }
    console.log(`Deployed Vault... (${vault.address})`);
    const strategyFactory: WaultWbnbVenusStrategy__factory = new WaultWbnbVenusStrategy__factory(deployer);
    let strategy: WaultWbnbVenusStrategy = strategyFactory.attach(strategyAddress).connect(deployer);
    if ("redeploy" && true) {
        strategy = await strategyFactory.deploy(vault.address);
    }
    console.log(`Deployed Strategy... (${strategy.address})`);

    console.log("Setting strategy address...");
    await vault.setStrategy(strategy.address);
    
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
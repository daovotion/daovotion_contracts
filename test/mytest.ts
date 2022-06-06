import { expect, assert } from "chai";
import { FixedNumber, ethers, BigNumber} from "ethers";
import {Greeter, Greeter__factory} from "../typechain-types";


/**
 * This Test needs a local running blockchain network, as it requires an existing wallet address
 */

const WALLET_ADDRESS_PK = "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80";
const NETWORK_ADDRESS_URL = "http://127.0.0.1:8545/";
const USE_PRIVATE_KEY = false;

describe("Greeter", function () {
  it("Should return the new greeting once it's changed", async function () {

    // connect to network
    let provider = null;

    try{
      provider = new ethers.providers.JsonRpcProvider(NETWORK_ADDRESS_URL);
    }catch(e){
      console.log("Error Provider instance ", e);
      provider = null;
    }
    
    assert(provider != null);

    console.log("Check if connected:\n");
    
    let network = null;
    try{
      network = await provider?.getNetwork();
    }catch(e){
      network = null;
      console.log("No network connected!!");
      console.log("|------------------------------------|");
      console.log(e);
      console.log("|------------------------------------|");
    }
    
    assert(network != null);

    // list accounts
    console.log("List accounts:\n");

    let accounts = await provider?.listAccounts();

    console.log(accounts);

    let signer = null;
    
    try{
      if(USE_PRIVATE_KEY){
        signer = new ethers.Wallet(WALLET_ADDRESS_PK, provider);
      }
      else{
        signer = provider.getSigner(0);
      }
      
    }catch(e){
      console.log("Cannot initialize Wallet signer.")
      console.log("|------------------------------------|");
      console.log(e);
      console.log("|------------------------------------|");
    }
    
    assert(signer != null);

    let signer_address:string = null;

    try{
      signer_address = await signer?.getAddress();
    }catch(e){
      console.log("Cannot connect wallet with address.")
      console.log("|------------------------------------|");
      console.log(e);
      console.log("|------------------------------------|");
    }
    
    assert(signer_address != null);

    console.log("connected to signer with address: ", signer_address);

    let balance:BigNumber = await signer.getBalance();

    console.log("Account balance : ", balance.toString());

    assert(balance.isZero() == false);

    const GreeterFac = new Greeter__factory(signer);

    const greeter = await GreeterFac.deploy("Hello, world!");
    await greeter.deployed();

    console.log("Contract deployed with address", greeter.address);

    expect(await greeter.greet()).to.equal("Hello, world!");

    const setGreetingTx = await greeter.setGreeting("Hola, mundo!");

    // wait until the transaction is mined
    await setGreetingTx.wait();

    expect(await greeter.greet()).to.equal("Hola, mundo!");
  });
  it("Just Waiting for fun", async function () {
    let val = 0;
    const fn = new Promise(function(resolve){
        setTimeout(resolve, 2000);
        val = 1;
    });

    await fn;

    expect(val == 1);
  });
});

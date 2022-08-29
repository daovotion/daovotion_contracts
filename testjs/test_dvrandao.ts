import { expect, assert } from "chai";
import { FixedNumber, ethers, BigNumber} from "ethers";
import {DVRANDAO, DVRANDAO__factory} from "../typechain-types";
import {stringify} from "json5";


/**
 * This Test needs a local running blockchain network, as it requires an existing wallet address
 */

const WALLET_ADDRESS_PK = "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80";
const NETWORK_ADDRESS_URL = "http://127.0.0.1:8545/";
const USE_PRIVATE_KEY = false;
const TARGET_WALLET0 = "0x70997970c51812dc3a010c7d01b50e0d17dc79c8";

interface IslandEntry
{
	address:string;
	islandID:BigNumber;
}

let generate_islands_fn = async function(island_ids:Array<IslandEntry>, contract:DVRANDAO){
	
	let tasks = [];
	for(let obj of island_ids)
	{
		let task = await contract.register_island(obj.islandID, obj.address);
		assert(task != null);		
		tasks.push(task.wait());
	}

	return Promise.all(tasks).then((results) => {
		for(let rs of results)
		{
			assert(rs != null);
			console.log("\n *** Island Created: \n\n", stringify(rs));
		}
	});
};

let generate_islands_fn1 = async function(island_ids:Array<IslandEntry>, contract:DVRANDAO){
	
	let tasks = island_ids.map(
		(obj:IslandEntry) => {
			return contract.register_island(obj.islandID, obj.address).then(txres => txres.wait());
		}
	);
	
	let txresults = Promise.all(tasks).then(
		results => {
			for(let rs of results)
			{
				assert(rs != null);
				console.log("\n *** Island Created: \n\n", stringify(rs));
			}
		}
	);	
	
};

interface CampaignEntry
{
	task:BigNumber;
	payment:PayableOverrides;
}


let generate_campaign_creations_fn = async function(campaign_set:Array<CampaignEntry>, contract:DVRANDAO){
	
	let tasks = [];
	for(let obj of campaign_set)
	{
		let task = await contract.create_new_task(obj.task, obj.payment);
		assert(task != null);		
		tasks.push(task.wait());
	}

	return Promise.all(tasks).then((results) => {
		for(let rs of results)
		{
			assert(rs != null);
			console.log("\n *** Campaign Created: \n\n", stringify(rs));
		}
	});
};

describe("DVRANDAO", function () {
  it("Test a Record Signature", async function () {

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

    console.log("|-----------------INSTANCE CONTRACT -------------------|");

    const DVRFac = new DVRANDAO__factory(signer);
    const dvrcontract = await DVRFac.deploy();
    await dvrcontract.deployed();

    console.log("** Contract DVRANDAO deployed with address", dvrcontract.address);

    console.log("|----------------- Obtain 2 addresses -------------------|");

    let account1 = null; let account2 = null;
    let account1_address:string = null; let account2_address:string = null;

    try{

      account1 = provider.getSigner(1);
      account2 = provider.getSigner(2);

    }catch(e)
    {
      console.log("Cannot obtain signers.")
      console.log("|------------------------------------|");
      console.log(e);
      console.log("|------------------------------------|");
    }

    try{

      account1_address = await account1?.getAddress();
      account2_address = await account2?.getAddress();

    }catch(e)
    {
      console.log("Cannot obtain signer addresses.")
      console.log("|------------------------------------|");
      console.log(e);
      console.log("|------------------------------------|");
    }
    
    console.log("Address1: ", account1_address);
    console.log("Address2: ", account2_address);

    console.log("|-----------------Register Island -------------------|");

	let islands_tasks = [
		{islandID:BigNumber.from(1), address: account1_address},
		{islandID:BigNumber.from(2), address: account2_address},
		{islandID:BigNumber.from(3), address: account1_address}
	];
	
    console.log("\nn|-----------------Transaction info (Island Creations) -------------------|");    
    
	await generate_islands_fn(islands_tasks, dvrcontract);

    console.log("\n\n|-----------------Task Creation -------------------|");

	let campaign_tasks = [
		{
			task:BigNumber.from(664),
			payment:{value: ethers.utils.parseEther("0.08")}
		},
		{
			task:BigNumber.from(574),
			payment:{value: ethers.utils.parseEther("0.18")}
		},
		{
			task:BigNumber.from(116),
			payment:{value: ethers.utils.parseEther("0.101")}
		}
	];
	
    console.log("\n|-----------------Transaction info (Tasks) -------------------|");
    
	await generate_campaign_creations_fn(campaign_tasks, dvrcontract);

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

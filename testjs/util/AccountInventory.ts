import {eINDEX32, SignedRecordEntry} from "./SignedRecordCEntry";
import {RandomAccounts, AccountInfo} from "./RandomAccounts";
import { BigNumber, Contract, ContractReceipt, ethers } from "ethers";
import { simulation } from "./VRFCircleProblem";
import { DVRANDAO, IVRFIslandDB, IVRFIslandDB__factory } from "../../typechain-types";
import {stringify} from "json5";

enum eVRF_RECORD_STATE
{
    VRF_RECORD_STATE_AVAILABLE = eINDEX32.INVALID_INDEX,
    VRF_RECORD_STATE_REVEALED = VRF_RECORD_STATE_AVAILABLE - 1,
    VRF_RECORD_STATE_FAULTED = VRF_RECORD_STATE_AVAILABLE - 2
}

interface ITxResult
{
    success:boolean;
    transaction?:ethers.ContractReceipt;
}

class SignedRecord
{
    public recordID:BigNumber;
    public entry:SignedRecordEntry;
    public proposal_index:number;
    
    constructor()
    {
        this.recordID = BigNumber.from(0);
        this.entry = new SignedRecordEntry();
        this.proposal_index = eVRF_RECORD_STATE.VRF_RECORD_STATE_AVAILABLE;
    }

    /**
     * The contract must be assigned to the island owner signer.
     * @param solution_circle 
     * @param island_id 
     * @param dvcontract 
     * @param signer 
     * @returns 
     */
    async register_record(
        solution_circle:simulation.VRFCircle,
        island_id:BigNumber,
        dvcontract:DVRANDAO) : Promise<ITxResult>
    {        
        let allowed = await this.entry.capture_params_for_new_record(island_id, dvcontract);
        if(allowed == false)
        {
            console.log("!!!Island ", island_id.toHexString(), " Not allowed to insert records!!");
            return {success:false};
        }

        this.entry.solution_circle = solution_circle;

        // generate signature
        await this.entry.generate_signature_fields(dvcontract.signer);

        
        let tx_record:ContractReceipt|null = null;
        // select method        
        if(this.entry.storage_fee.isZero())
        {
            let parityv = BigNumber.from(this.entry.sign_v);
            // insert record working
            let tx = await dvcontract.insert_record_solving(
                island_id,
                this.entry.sign_r,
                this.entry.sign_s,
                parityv
            );

            tx_record = await tx.wait();
        }
        else if(this.entry.storage_fee == BigNumber.from(1))
        {
            // insert with bonus
            let parityv = BigNumber.from(this.entry.sign_v);
            // insert record working
            let tx = await dvcontract.insert_record_bonus(
                island_id,
                this.entry.sign_r,
                this.entry.sign_s,
                parityv
            );

            tx_record = await tx.wait();
        }
        else
        {            
            // insert with storage fee
            let parityv = BigNumber.from(this.entry.sign_v);
            // insert record working
            let tx = await dvcontract.insert_record(
                island_id,
                this.entry.sign_r,
                this.entry.sign_s,
                parityv,
                {value:this.entry.storage_fee}
            );

            tx_record = await tx.wait();
        }

        if(!tx_record || tx_record === null)
        {
            throw Error("Transaction cancelled");
        }

        // fill record ID
        // check events
        let record_event_filter = dvcontract.filters.NewRecordSigned;

        let event_buffer = await dvcontract.queryFilter(
            record_event_filter,
            tx_record.blockNumber,
            tx_record.blockNumber
        );

        if(Array.isArray(event_buffer) == false || event_buffer.length != 1)
        {
            throw Error("Cannot capture Signed record field");
        }

        let event_params = event_buffer[0].args;

        // third parameter
        this.recordID = BigNumber.from(event_params[2]);

        
        return {success:true, transaction:tx_record};
    }

    public verify_signature(src_address:string): boolean
    {
        return this.entry.verify_signature(src_address);
    }

    public async verify_dao_signature(dvcontract:DVRANDAO, src_address:string): Promise<boolean>
    {
        return await this.entry.verify_dao_signature(dvcontract, this.recordID, src_address);
    }
}

interface IRecordIslandTxResult
{
    success:boolean;
    recordID?:BigNumber;
    storage_fee?:BigNumber;
    rng_seed?:bigint;
    transaction?:ContractReceipt;
}

class IslandRecordSet
{
    islandID:BigNumber;
    records:Array<SignedRecord>;

    constructor(island_id:BigNumber)
    {
        this.islandID = island_id;
        this.records = new Array<SignedRecord>();
    }

    /**
     * The contract must be assigned to the island owner signer.
     * @param problem 
     * @param rng_seed 
     * @param dvcontract 
     * @return The next random seed and the status of the insertion.
     */
    async insert_simulated_circle(
        problem:simulation.VRFCircleProblem,
        rng_seed:bigint,
        dvcontract:DVRANDAO):Promise<IRecordIslandTxResult>
    {
        // generated simulated circle
        let new_circle_entry = problem.generate_test_circle(rng_seed, 100);
        if(new_circle_entry.circle.radius <= BigInt(0))
        {
            console.log("!!Maximum number of iterations, no solution available!!");
            console.log("with seed ", BigNumber.from(new_circle_entry.rng_seed).toHexString());
            return {success:false, rng_seed:new_circle_entry.rng_seed};
        }
        
        let new_record = new SignedRecord();

        let tx_record = await new_record.register_record(new_circle_entry.circle, this.islandID, dvcontract);
        if(tx_record.success && tx_record.transaction)
        {
            this.records.push(new_record);
            return {
                success:true,
                rng_seed:new_circle_entry.rng_seed,
                recordID:new_record.recordID,
                storage_fee:new_record.entry.storage_fee,
                transaction:tx_record.transaction
            };
        }

        return {success:false, rng_seed:new_circle_entry.rng_seed};
    }

    public verify_records_signature(src_address:string): boolean
    {
        let ret_val = true;
        for(let robj of this.records)
        {
            let bval = robj.verify_signature(src_address);
            if(bval == false)
            {
                console.log("!!!----------------------------------------------------------!!!");
                console.log("!!!Record ", robj.recordID.toHexString(), " has bad signature (local)!!!");
                console.log("!!!On Island ", this.islandID.toHexString()," !!!");
                console.log("!!!Owner: ", src_address," !!!");
                console.log("!!!----------------------------------------------------------!!!");
                ret_val = false;
            }
        }

        return ret_val;
    }

    public async verify_records_signature_on_dao(dvcontract:DVRANDAO, src_address:string): Promise<boolean>
    {
        let ret_val = true;
        for(let robj of this.records)
        {
            let bval = await robj.verify_dao_signature(dvcontract, src_address);
            if(bval == false)
            {
                console.log("!!!----------------------------------------------------------!!!");
                console.log("!!!Record ", robj.recordID.toHexString(), " has bad signature!!!");
                console.log("!!!On Island ", this.islandID.toHexString()," !!!");
                console.log("!!!Owner: ", src_address," !!!");
                console.log("!!!----------------------------------------------------------!!!");
                ret_val = false;
            }
        }

        return ret_val;
    }
}

class AccountIslandCollection
{
    islands:Array<IslandRecordSet>;

    constructor()
    {
        this.islands = Array<IslandRecordSet>();
    }

    public reset_accounts()
    {
        this.islands.length = 0;
    }

    public async generate_islands(pk_owner:string, start_index:BigNumber, dvcontract:DVRANDAO, num_islands:number)
    {
        let tasks = [];
        // 1 based sequence.
        for(let i = 0; i < num_islands; i++)
        {
            let new_islandID = start_index.add(BigNumber.from(i + 1));

            // create local instance
            this.islands.push(new IslandRecordSet(new_islandID));

            // call contract
            let tx = await dvcontract.register_island(new_islandID, pk_owner);
            tasks.push(tx.wait());
        }

        return Promise.all(tasks);        
    }

    public async insert_rnd_records(
        problem:simulation.VRFCircleProblem, 
        rng_seed:bigint, 
        dvcontract:DVRANDAO,
        signer:ethers.Signer): Promise<bigint>
    {
        let src_addr = await signer.getAddress();
        let client_contract = dvcontract.connect(signer);
        let ret_seed_number:bigint = rng_seed;
        for(let iobj of this.islands)
        {
            let ret_params = await iobj.insert_simulated_circle(problem, ret_seed_number, client_contract);
            // return rng seed
            if(!ret_params.rng_seed)
            {
                throw Error("Function insert_simulated_circle should return RNG seed.");
            }

            ret_seed_number = ret_params.rng_seed;

            if(ret_params.success && ret_params.recordID && ret_params.transaction)
            {
                console.log("\n**-> Record Success: ", ret_params.recordID);
                console.log("*** IslandID: ", iobj.islandID.toHexString());
                console.log("*** Storage Fee = ", ret_params.storage_fee);
                let last_element = iobj.records.at(iobj.records.length - 1);
                if(!last_element) throw Error("Circle???");
                console.log("*** Circle:\n ", last_element.entry.solution_circle.toString());
                console.log("|-------------------------------|");
                console.log(stringify(ret_params.transaction));
                console.log("|-------------------------------|");
            }
            else
            {
                console.log("\n**-> Record Insertion Failure!!!");
                console.log("*** Island : ", iobj.islandID.toHexString());                
                console.log("*** Account : ", src_addr);
                console.log("*****************************************");
            }
            
        }

        return ret_seed_number;
    }


    public verify_records_signature(src_address:string): boolean
    {
        let ret_val = true;
        for(let iobj of this.islands)
        {
            let bval = iobj.verify_records_signature(src_address);
            if(bval == false)
            {
                ret_val = false;
            }
        }

        return ret_val;
    }

    public async verify_records_signature_on_dao(dvcontract:DVRANDAO, src_address:string): Promise<boolean>
    {
        let ret_val = true;
        for(let iobj of this.islands)
        {
            let bval = await iobj.verify_records_signature_on_dao(dvcontract, src_address);
            if(bval == false)
            {
                ret_val = false;
            }
        }

        return ret_val;
    }
}

class AccountInventory
{
    accounts:RandomAccounts;
    problem_simulation:simulation.VRFCircleProblem;
    rng_seed:bigint;

    constructor()
    {
        this.accounts = new RandomAccounts();
        this.problem_simulation = new simulation.VRFCircleProblem();
        const rnd_data_bytes = ethers.utils.randomBytes(32);
        this.rng_seed = BigNumber.from(rnd_data_bytes).toBigInt();
    }

    async generate_accounts_and_islands(
        num_accounts:number,
        islands_x_account:number, 
        dvcontract:DVRANDAO,
        provider:ethers.providers.Provider)
    {
        this.rng_seed = await this.accounts.insert_random_by_seed(this.rng_seed, num_accounts, provider);

        let island_tasks = new Array<{pkowner:string, collection:AccountIslandCollection}>();
        // fill accounts with island inventory
        this.accounts.process_all((ainfo:AccountInfo) => {
            let island_collection = new AccountIslandCollection();
            ainfo.data = island_collection;
            island_tasks.push({pkowner:ainfo.public_key, collection:island_collection});
        });

        // Generate islands for accounts
        if(islands_x_account == 0) return;

        // generate islands on each inventory
        let island_index = BigNumber.from(0);

        for(let task of island_tasks)
        {
            await task.collection.generate_islands(task.pkowner, island_index, dvcontract, islands_x_account);
            island_index = island_index.add(BigNumber.from(islands_x_account));
        }
    }

    async check_islands_ownership(dvcontract:DVRANDAO):Promise<boolean>
    {

        // get contract
        let island_db_addr = await dvcontract.get_islands_contract();

        console.log("** Obtaining Islands DB contract for ", island_db_addr );

        // obtain contract
        let island_db_contract:IVRFIslandDB = IVRFIslandDB__factory.connect(island_db_addr, dvcontract.signer);
        

        let island_tasks = new Array<{pkowner:string, collection:AccountIslandCollection}>();
        // fill accounts with island inventory
        this.accounts.process_all((ainfo:AccountInfo) => {
            let island_collection:AccountIslandCollection = ainfo.data as AccountIslandCollection;                        
            island_tasks.push({pkowner:ainfo.public_key, collection:island_collection});
        });


        let ret_success = true;

        for(let task of island_tasks)
        {
            console.log("\n|--> Account = ", task.pkowner," --|\n");

            for(let island_info of task.collection.islands)
            {
                console.log("* Island ", island_info.islandID.toHexString());
                // extract owner from randao
                let _account = await island_db_contract.get_island_owner(island_info.islandID);
                console.log("** -> Address = ", _account);

                if(_account != task.pkowner)
                {
                    ret_success = false;
                }
            }
        }
        return ret_success;
    }

    public async inyect_funds(src_wallet:ethers.Signer, ammount:BigNumber)
    {
        await this.accounts.inyect_funds(src_wallet, ammount);
    }

    public async insert_random_records(dvcontract:DVRANDAO)
    {
        // Configure problem random
        this.problem_simulation.reset_problem();
        console.log("Generating problem with seed ", this.rng_seed.toString());
        const params = this.problem_simulation.generate_static_circles(16, 1000, this.rng_seed);        
        this.rng_seed = params.rng_seed;

        if(this.problem_simulation.circle_count() < 16)
        {
            throw Error("Malformed problem with seed " + this.rng_seed.toString());
        }
        
        console.log("\n|--------------------------------------------------------|");
        console.log("Problem generated in ", params.num_iterations, " iterations.\n");
        console.log(this.problem_simulation.toString());
        console.log("|--------------------------------------------------------|\n");

        let island_tasks = new Array<{address:string, account_signer:ethers.Signer, collection:AccountIslandCollection}>();
        this.accounts.process_all((ainfo:AccountInfo) => {
            let island_collection:AccountIslandCollection = ainfo.data as AccountIslandCollection;            
            island_tasks.push({address:ainfo.public_key, account_signer:ainfo.signer, collection:island_collection});
        });

        // process all transactions
        for(let task of island_tasks)
        {
            console.log("\n|--------------------Account Record insertion----------------------------|");
            console.log("|-- For Address ",task.address,"--|");

            let balance = await task.account_signer.getBalance();
            console.log("|-- Balance = ",balance.toString(),"--|");

            let colset = task.collection;
            this.rng_seed = await colset.insert_rnd_records(
                this.problem_simulation, 
                this.rng_seed,
                dvcontract, task.account_signer
            );


            balance = await task.account_signer.getBalance();
            console.log("|-- Balance After = ",balance.toString(),"--|");
        }
    }

    public verify_records_signature() : boolean
    {
        let island_tasks = new Array<{address:string, collection:AccountIslandCollection}>();
        this.accounts.process_all((ainfo:AccountInfo) => {
            let island_collection:AccountIslandCollection = ainfo.data as AccountIslandCollection;            
            island_tasks.push({address:ainfo.public_key, collection:island_collection});
        });

        let ret_val = true;
        // process all transactions
        for(let task of island_tasks)
        {
            let bval = task.collection.verify_records_signature(task.address);
            if(bval == false)
            {
                ret_val = false;
            }
        }

        return ret_val;
    }

    public async verify_records_signature_on_dao(dvcontract:DVRANDAO): Promise<boolean>
    {
        let island_tasks = new Array<{address:string, collection:AccountIslandCollection}>();
        this.accounts.process_all((ainfo:AccountInfo) => {
            let island_collection:AccountIslandCollection = ainfo.data as AccountIslandCollection;            
            island_tasks.push({address:ainfo.public_key, collection:island_collection});
        });

        let ret_val = true;
        // process all transactions
        for(let task of island_tasks)
        {
            let bval = await task.collection.verify_records_signature_on_dao(dvcontract, task.address);
            if(bval == false)
            {
                ret_val = false;
            }
        }

        return ret_val;
    }

}

export {AccountInventory, AccountIslandCollection, IslandRecordSet, SignedRecord, eVRF_RECORD_STATE}
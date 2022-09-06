import { BigNumber, ethers} from "ethers";
import { pcgsha256random } from "./PCGRandom";

class AccountInfo
{
	public signer:ethers.Signer;
	public public_key:string;
	public data:object|null;

	constructor(_public_key:string, _signer:ethers.Signer)
	{
		this.signer = _signer;
		this.public_key = _public_key;
		this.data = null;
	}

	static async create(signer:ethers.Signer):Promise<AccountInfo>
	{
		let pk = await signer.getAddress();
		if(!pk)
		{
			throw Error("Cannot create public address");
		}
		return Promise.resolve(new AccountInfo(pk, signer));
	}
}

class RandomAccounts
{
	accounts:Map<string, AccountInfo>;
	
	constructor()
	{
		this.accounts = new Map<string, AccountInfo>();
	}

	protected async insert_record(signer:ethers.Signer):Promise<boolean>
	{		
		let new_record = await AccountInfo.create(signer);

		// check collision
		if(this.accounts.has(new_record.public_key))
		{
			console.log("Collision of account ", new_record.public_key);
			return false;
		}

		this.accounts.set(new_record.public_key, new_record);
		return true;
	}

	public get_account_data(account_key:string):object|null
	{
		if(this.accounts.has(account_key) == false) return null;
		let ainfo = this.accounts.get(account_key);
		if(ainfo) return ainfo.data;
		return null;
	}

	public async account_balance(account_key:string):Promise<BigNumber>
	{
		if(this.accounts.has(account_key) == false) return BigNumber.from(0);
		let ainfo = this.accounts.get(account_key);
		if(ainfo)
		{
			return ainfo.signer.getBalance();
		} 
		return BigNumber.from(0);
	}

	public set_account_data(account_key:string, data:object|null):boolean
	{
		if(this.accounts.has(account_key) == false) return false;
		let ainfo = this.accounts.get(account_key);
		if(!ainfo) return false;
		ainfo.data = data;
		return true;
	}

	/**
	 * 
	 * @param rng_seed 
	 * @param num_accounts 
	 */
	public async insert_random_by_seed(rng_seed:bigint, num_accounts:number, provider:ethers.providers.Provider) : Promise<bigint>
	{
		let rng_params = pcgsha256random.next_value(rng_seed);
		for(let i = 0; i < num_accounts; i++)
		{
			let private_key = BigNumber.from(rng_params.rnd_number).toHexString();
			rng_params = pcgsha256random.next_value(rng_params.seed_rng); // update random

			await this.insert_record(new ethers.Wallet(private_key, provider));			
		}
		return rng_params.seed_rng;
	}

	public async insert_random(num_accounts:number)
	{
		for(let i = 0; i < num_accounts; i++)
		{
			// create wallet with custom private key
			await this.insert_record(ethers.Wallet.createRandom());
		}
	}

	public async inyect_funds(src_wallet:ethers.Signer, ammount:BigNumber)
	{
		for(let ainfo of this.accounts.values())
		{
			await src_wallet.sendTransaction({to:ainfo.public_key, value:ammount});
		}
	}

	public process_all(process_fn:(ainfo:AccountInfo) => void)
	{
		for(let ainfo of this.accounts.values())
		{
			process_fn(ainfo);
		}
	}
}

export {AccountInfo, RandomAccounts}
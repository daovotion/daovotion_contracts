import { BigNumber, ethers} from "ethers";
import {simulation} from "./VRFCircleProblem";
import {DVRANDAO} from "../../typechain-types";

enum eINDEX32
{
	INVALID_INDEX = 0xffffffff
}

class SignedRecordEntry
{
	solution_circle:simulation.VRFCircle;
	campaignID:BigNumber;
	islandID:BigNumber;
	island_index:number;
	storage_fee:BigNumber;
	sign_s:string;
	sign_r:string;
	sign_v:number;
	
	constructor()
	{
		this.solution_circle = new simulation.VRFCircle();
		this.campaignID = BigNumber.from(0);
		this.islandID = BigNumber.from(0);
		this.island_index = 0;
		this.storage_fee = BigNumber.from(0);
		this.sign_s = "";
		this.sign_r = "";
		this.sign_v = 0;
	}

	public parse_params_from_tx_data(data:ethers.BytesLike)
	{
		const encoder = new ethers.utils.AbiCoder();
		const _struct = encoder.decode(["uint256", "uint32", "uint256"], data);

		if((typeof _struct == undefined) || _struct == null)
		{
			throw Error("Cannot read parameters for signature generation.");
		}
		else if(_struct.length != 3)
		{
			throw Error("Malformed parameters for signature generation.");
		}

		console.log("Parsed tuple ", JSON.stringify(_struct));

		this.campaignID = _struct[0][0];
		this.island_index = _struct[0][1];
	}

	public encode_params_buffer() : string
	{
		/// (islandID, campaingID, island_campaign_index, cx,  cy, radius)
		const encoder = new ethers.utils.AbiCoder();
		return encoder.encode(
			["uint256", "uint256", "uint32", "int64", "int64", "int64"],
			[
				this.islandID, this.campaignID, this.island_index,
				BigNumber.from(this.solution_circle.x), 
				BigNumber.from(this.solution_circle.y),
				BigNumber.from(this.solution_circle.radius)
			]
		);
	}

	public encode_params_hash():Uint8Array
	{
		return ethers.utils.arrayify(
            ethers.utils.keccak256(this.encode_params_buffer())
        );
	}

	public async capture_params_for_new_record(island_id:BigNumber, contract:DVRANDAO) : Promise<boolean>
	{
		this.islandID = island_id;

		const txdata = await contract.suggested_record_indexparams(BigNumber.from(island_id));

        if(Array.isArray(txdata) == false || txdata.length != 3)
        {
            throw Error("Malformed record params");
        }
		
		this.campaignID = txdata[0];
		this.island_index = txdata[1];
		this.storage_fee = txdata[2];
		return this.island_index != eINDEX32.INVALID_INDEX;
	}

	public async generate_signature_fields(signer:ethers.Signer)
	{
		let params_hash = this.encode_params_hash();
		let signed_data = await signer.signMessage(params_hash);
		// split signature
		let signature = ethers.utils.splitSignature(signed_data);
		this.sign_r = signature.r;
		this.sign_s = signature.s;
		this.sign_v = signature.v;
	}

	public verify_signature(src_address:string):boolean
	{
		let params_hash = this.encode_params_hash();
		// let sign_data = ethers.utils.joinSignature({r:this.sign_r, s:this.sign_s, v:this.sign_v});
		let addr = ethers.utils.verifyMessage(
            params_hash,
            {r:this.sign_r, s:this.sign_s, v:this.sign_v}
        );
		return addr == src_address;
	}

    public async verify_dao_signature(dvcontract:DVRANDAO, recordID:BigNumber, src_address:string): Promise<boolean>
    {
        let bval = await dvcontract.is_valid_record_signature(
            recordID, 
            src_address,
            BigNumber.from(this.solution_circle.x),
            BigNumber.from(this.solution_circle.y),
            BigNumber.from(this.solution_circle.radius)
        );
        return bval;
    }
}

export {SignedRecordEntry, eINDEX32}
import { BigNumber, ethers} from "ethers";

/*
 * TypeScript implementation for DAOVOTION. This version generates 32bit Random numbers based
 * on the algoritm from Melissa O'Neill, which is statistically efficient and correct. More info at 
 * http://www.pcg-random.org
 */

namespace pcg32random
{
    const PCG32_MULTIPLIER:bigint = BigInt("6364136223846793005");
    const PCG32_INC:bigint = BigInt("1442695040888963407");
    // Output function XSH RR: xorshift high (bits), followed by a random rotate
    // Constants are for 64-bit state, 32-bit output
    const PCG32_ROTATE:bigint = 59n; // 64 - 5
    const PCG32_XSHIFT:bigint = 18n; // (5 + 32) / 2
    const PCG32_SPARE:bigint = 27n; // 64 - 32 - 5	
    const UINT32_MASK:bigint = 0xffffffffn;
    const UINT64_MASK:bigint = 0xffffffffffffffffn;


    export function i32_rotate_right(value:bigint, bitcount:bigint):bigint
    {
        let clapnumber = value & UINT32_MASK;
        // clap rotation
        let bshift = bitcount & 31n;
        return ((clapnumber << bshift) & UINT32_MASK) | (clapnumber >> (32n - bshift));
    }

    export function i64_rotate_right(value:bigint, bitcount:bigint):bigint
    {
        let clapnumber = value & UINT64_MASK;
        // clap rotation
        let bshift = bitcount & 63n;
        return ((clapnumber << bshift) & UINT64_MASK) | (clapnumber >> (64n - bshift));
    }

    export function advance_state(pcgstate:bigint):bigint
    {
        return (pcgstate * PCG32_MULTIPLIER) + PCG32_INC;
    }

    export function rng_value(pcgstate:bigint):bigint
    {
        let rot:bigint = pcgstate >> PCG32_ROTATE;
        let xsh:bigint = (((pcgstate >> PCG32_XSHIFT) ^ pcgstate) >> PCG32_SPARE);
        return i32_rotate_right(xsh, rot);
    }
}

namespace pcgsha256random
{
    export const debug_print_rng_bytes_generation = false;

    interface IPCGSha256State
    {
        state0:bigint;
        state1:bigint;
        state2:bigint;
        state3:bigint;
    }

    function configure(seed:bigint):IPCGSha256State
    {
        const mask64:bigint = BigInt("0xffffffffffffffff");
        
        return {
            state0: seed & mask64,
            state1: (seed >> BigInt(64)) & mask64,
            state2: (seed >> BigInt(128)) & mask64,
            state3: (seed >> BigInt(192)) & mask64
        };		
    }

    export function get_seed256(pcgstate:IPCGSha256State):bigint
    {
        let retval = pcgstate.state0 | (pcgstate.state1 << BigInt(64));		
        retval |= pcgstate.state2 << BigInt(128);
        retval |= pcgstate.state3 << BigInt(192);
        return retval;
    }

    export interface IPCGSha256Params
    {
        rnd_number:bigint;
        seed_rng:bigint;
    }

    export function next_value(seed_rng:bigint): IPCGSha256Params
    {
        let pcgstate = configure(seed_rng);
        let u32buffer = new ArrayBuffer(32);
        let valu32 = new Uint32Array(u32buffer);		
        let _state:bigint = pcg32random.advance_state(pcgstate.state0);
        valu32[0] = Number(pcg32random.rng_value(_state));		
        _state = BigInt(pcg32random.advance_state(_state));
        valu32[1]= Number(pcg32random.rng_value(_state));		
        let new_state3:bigint = BigInt(_state.toString());// first state0
        
        _state = BigInt(pcg32random.advance_state(pcgstate.state1));
        valu32[2] = Number(pcg32random.rng_value(_state));
        _state = BigInt(pcg32random.advance_state(_state));
        valu32[3] = Number(pcg32random.rng_value(_state));
        let new_state2 = BigInt(_state.toString());// state1
        
        _state = BigInt(pcg32random.advance_state(pcgstate.state2));
        valu32[4] = Number(pcg32random.rng_value(_state));
        _state = BigInt(pcg32random.advance_state(_state));
        valu32[5] = Number(pcg32random.rng_value(_state));
        let new_state0 = BigInt(_state.toString()); // state2
        
        _state = BigInt(pcg32random.advance_state(pcgstate.state3));
        valu32[6] = Number(pcg32random.rng_value(_state));
        _state = BigInt(pcg32random.advance_state(_state));
        valu32[7] = Number(pcg32random.rng_value(_state));
        let new_state1 = BigInt(_state.toString()); // state3
        
        let _encoded_buffer = new Uint8Array(valu32);
        
        let _next_number_data = ethers.utils.keccak256(_encoded_buffer);

        if(debug_print_rng_bytes_generation)
        {
            console.log("rnduint32=", JSON.stringify(valu32));
            console.log("rndbytes=", _next_number_data);
        }	

        let next_number = BigNumber.from(_next_number_data).toBigInt();
        let next_seed = get_seed256({
            state0:new_state0,
            state1:new_state1,
            state2:new_state2,
            state3:new_state3
        });

        return {rnd_number:next_number,seed_rng: next_seed};
    }
}

export {pcg32random, pcgsha256random}
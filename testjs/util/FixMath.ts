import { BigNumber} from "ethers";

namespace fix64
{
	export const DV_FIX64_FRACBITS:bigint = BigInt(32);
	export const DV_FIX64_NAN:bigint = -BigInt("0x7fffffffffffffff");

	export function i32_to_fix(val0:number) : bigint 
	{
        return BigInt(val0) << DV_FIX64_FRACBITS;
    }

	export function mul(val0:bigint, val1:bigint) : bigint
	{
        let _bignum:bigint = val0 * val1;
        return _bignum >> DV_FIX64_FRACBITS;
    }

	export function div(value:bigint, divisor:bigint) : bigint
	{
        if (divisor == 0n) 
		{
            return DV_FIX64_NAN;
        }

        let _bignum:bigint = value << DV_FIX64_FRACBITS;
        return _bignum / divisor;
    }

	export function toBigNumber(val:bigint) : BigNumber
	{
		return BigNumber.from(val);
	}
}

export {fix64}
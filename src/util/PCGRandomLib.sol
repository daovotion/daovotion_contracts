//SPDX-License-Identifier:MIT
pragma solidity >=0.8.8;

/*
 * Solidity implementation for DAOVOTION. This version generates 32bit Random numbers based
 * on the algoritm from Melissa O'Neill, which is statistically efficient and correct. More info at 
 * http://www.pcg-random.org
 */
library PCG32RandomLib
{
	uint64 constant PCG32_MULTIPLIER = 6364136223846793005;
	uint64 constant PCG32_INC = 1442695040888963407;
	// Output function XSH RR: xorshift high (bits), followed by a random rotate
	// Constants are for 64-bit state, 32-bit output
	uint64 constant PCG32_ROTATE = 59; // 64 - 5
	uint64 constant PCG32_XSHIFT = 18; // (5 + 32) / 2
	uint64 constant PCG32_SPARE = 27; // 64 - 32 - 5

	function i32_rotate_right(uint32 value, uint32 bitcount) internal pure returns(uint32)
	{
		// clap rotation
		uint32 bshift = bitcount & 31;
		uint32 retval = 0;
		unchecked {
			retval = value << bshift | value >> (32 - bshift);
		}

		return retval;
	}

	function i64_rotate_right(uint64 value, uint64 bitcount) internal pure returns(uint64)
	{
		// clap rotation
		uint64 bshift = bitcount & 63;
		uint64 retval = 0;
		unchecked {
			retval = value << bshift | value >> (64 - bshift);
		}

		return retval;
	}

	/// Update the sequence
	function advance_state(uint64 pcgstate) internal pure returns(uint64)
	{
		uint64 _state = pcgstate;
		unchecked {
			_state = (_state * PCG32_MULTIPLIER) + PCG32_INC;
		}
		return _state;
	}

	function rng_value(uint64 pcgstate) internal pure returns(uint32)
	{      
		uint64 rot = pcgstate >> PCG32_ROTATE;
		uint64 xsh = (((pcgstate >> PCG32_XSHIFT) ^ pcgstate) >> PCG32_SPARE);
		return i32_rotate_right(uint32(xsh), uint32(rot));
	}
}


// A composed random combinator for 256bit based on SHA-3
struct PCGSha256RandomState
{
	uint64 state0;
	uint64 state1;
	uint64 state2;
	uint64 state3;
}


library PCGSha256RandomLib
{
	function configure(PCGSha256RandomState storage pcgstate, uint256 seed) internal
	{
		uint256 mask64 = 0xffffffffffffffff;
		pcgstate.state0 = uint64(seed & mask64);
		pcgstate.state1 = uint64((seed >> 64) & mask64);
		pcgstate.state2 = uint64((seed >> 128) & mask64);
		pcgstate.state3 = uint64((seed >> 192) & mask64);
	}

	function configure_mem(PCGSha256RandomState memory pcgstate, uint256 seed) internal pure
	{
		uint256 mask64 = 0xffffffffffffffff;
		pcgstate.state0 = uint64(seed & mask64);
		pcgstate.state1 = uint64((seed >> 64) & mask64);
		pcgstate.state2 = uint64((seed >> 128) & mask64);
		pcgstate.state3 = uint64((seed >> 192) & mask64);
	}

	function get_seed256(PCGSha256RandomState storage pcgstate) internal view returns(uint256)
	{
		uint256 retval = uint256(pcgstate.state0);
		retval |= uint256(pcgstate.state1) << 64;
		retval |= uint256(pcgstate.state2) << 128;
		retval |= uint256(pcgstate.state3) << 192;
		return retval;
	}

	function get_seed256_mem(PCGSha256RandomState memory pcgstate) internal pure returns(uint256)
	{
		uint256 retval = uint256(pcgstate.state0);
		retval |= uint256(pcgstate.state1) << 64;
		retval |= uint256(pcgstate.state2) << 128;
		retval |= uint256(pcgstate.state3) << 192;
		return retval;
	}

	function next_value(PCGSha256RandomState storage pcgstate) internal returns(uint256)
	{
		uint32[8] memory valu32;
		uint64 _state = PCG32RandomLib.advance_state(pcgstate.state0);
		valu32[0] = PCG32RandomLib.rng_value(_state);
		_state = PCG32RandomLib.advance_state(_state);
		valu32[1] = PCG32RandomLib.rng_value(_state);
		pcgstate.state3 = _state;// first state0
		
		_state = PCG32RandomLib.advance_state(pcgstate.state1);
		valu32[2] = PCG32RandomLib.rng_value(_state);
		_state = PCG32RandomLib.advance_state(_state);
		valu32[3] = PCG32RandomLib.rng_value(_state);
		pcgstate.state2 = _state;// state1
		
		_state = PCG32RandomLib.advance_state(pcgstate.state2);
		valu32[4] = PCG32RandomLib.rng_value(_state);
		_state = PCG32RandomLib.advance_state(_state);
		valu32[5] = PCG32RandomLib.rng_value(_state);
		pcgstate.state0 = _state; // state2
		
		_state = PCG32RandomLib.advance_state(pcgstate.state3);
		valu32[6] = PCG32RandomLib.rng_value(_state);
		_state = PCG32RandomLib.advance_state(_state);
		valu32[7] = PCG32RandomLib.rng_value(_state);
		pcgstate.state1 = _state; // state3

		return uint256(keccak256(abi.encodePacked(valu32)));      
	}

	function next_value_mem(PCGSha256RandomState memory pcgstate) internal pure returns(uint256)
	{
		uint32[8] memory valu32;
		uint64 _state = PCG32RandomLib.advance_state(pcgstate.state0);
		valu32[0] = PCG32RandomLib.rng_value(_state);
		_state = PCG32RandomLib.advance_state(_state);
		valu32[1] = PCG32RandomLib.rng_value(_state);
		pcgstate.state3 = _state;// first state0
		
		_state = PCG32RandomLib.advance_state(pcgstate.state1);
		valu32[2] = PCG32RandomLib.rng_value(_state);
		_state = PCG32RandomLib.advance_state(_state);
		valu32[3] = PCG32RandomLib.rng_value(_state);
		pcgstate.state2 = _state;// state1
		
		_state = PCG32RandomLib.advance_state(pcgstate.state2);
		valu32[4] = PCG32RandomLib.rng_value(_state);
		_state = PCG32RandomLib.advance_state(_state);
		valu32[5] = PCG32RandomLib.rng_value(_state);
		pcgstate.state0 = _state; // state2
		
		_state = PCG32RandomLib.advance_state(pcgstate.state3);
		valu32[6] = PCG32RandomLib.rng_value(_state);
		_state = PCG32RandomLib.advance_state(_state);
		valu32[7] = PCG32RandomLib.rng_value(_state);
		pcgstate.state1 = _state; // state3

		return uint256(keccak256(abi.encodePacked(valu32)));      
	}

}
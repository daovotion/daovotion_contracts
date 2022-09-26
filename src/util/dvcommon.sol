//SPDX-License-Identifier:MIT
pragma solidity >=0.8.8;

uint256 constant DV_PERCENTAJE_FACTOR = 10000;

uint256 constant DV_UPPER_TOKEN_MASK_BIT_COUNT = 192;

// Also is the token mask
uint256 constant DV_MAX_TOKEN_VALUE = (uint256(1) << DV_UPPER_TOKEN_MASK_BIT_COUNT) - uint256(1);

uint256 constant DV_UPPER_TOKEN_MASK = ~DV_MAX_TOKEN_VALUE;

uint32 constant INVALID_INDEX32 = 0xffffffff;

uint64 constant INVALID_INDEX64 = 0xffffffffffffffff;

uint256 constant DV_DEFAULT_TOKEN_ID = 1; // A reference value that is not used and could indicates a null.

uint256 constant DV_MAX_INSURANCE_PERCENTAJE = 5000;//50%
uint256 constant DV_MAX_INSURANCE_RISK_THRESHOLD = 5000;//50%
uint256 constant DV_MIN_INSURANCE_RISK_THRESHOLD = 100;//1%


// Prestige Grace Periods parameters
//
uint32 constant DV_ACCREDITED_AGE_INIT = 3;
uint32 constant DV_PIONEER_SPONSOR_PLANET_CURVE = 9;
uint32 constant DV_AGE_FOR_SPONSORSHIP = 9;
//


// Star promotion status
//
int16 constant DV_STATUS_UNACCREDITED = 0;
int16 constant DV_STATUS_PROMOTING = -1;
int16 constant DV_STATUS_GUILTY = -2;
int16 constant DV_STATUS_REDEMPTION = -3;
int16 constant DV_STATUS_ACCREDITED = 1;
int16 constant DV_STATUS_PARDONED = 2;
int16 constant DV_STATUS_SPONSORSHIP_BONUS = 4;
int16 constant DV_STATUS_HONORABLE_BONUS = 8;
int16 constant DV_STATUS_HONORABLE_SPONSOR_BONUS = 12;
int16 constant DV_STATUS_SPONSORSHIP_EXTRA_BONUS = 16;
//

// Token types
//
uint256 constant DV_NUCLEUS_TOKEN = 1;
uint256 constant DV_STAR_TOKEN = 2;
uint256 constant DV_PLANET_TOKEN = 3;
uint256 constant DV_ISLAND_TOKEN = 4;
uint256 constant DV_RING_TOKEN = 5;
uint256 constant DV_PUZZLE_TOKEN = 6;
uint256 constant DV_ARCHANGEL_TOKEN = 7;
///

bytes32 constant DV_NULL_NAME = bytes32(0);

function DVF_PERCENTAJE(uint256 _price, uint256 _percentaje) pure returns(uint256)
{
    return (_price * _percentaje) /  DV_PERCENTAJE_FACTOR;
}


function DVF_ADDRtoU256(address _address)  pure returns(uint256)
{
    return uint256(uint160(_address));
}


function DVF_U256toADDR(uint256 _address)  pure returns(address)
{
    return address(uint160(_address));
}

function DVF_IsNullName(bytes32 strname) pure returns(bool)
{
    return strname == DV_NULL_NAME;
}

// common errors
error ErrDAO_InvalidParams();

error ErrDAO_UnauthorizedAccess();
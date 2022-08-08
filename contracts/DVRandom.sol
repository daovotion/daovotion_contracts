//SPDX-License-Identifier:MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "./DVList.sol";


uint256 constant DV_PERCENTAJE_FACTOR = 10000;

// VRF Fix point
uint constant DV_FIX64_FRACBITS = 32;
int64 constant DV_FIX64_NAN = -0x7fffffffffffffff;

// VRF Problem
uint32 constant VRF_CIRCLES_COUNT = 16;
int64 constant VRF_PROBLEM_AREA = 0x20000000000;//512.00 fix32
int64 constant VRF_PROBLEM_MAXRADIUS = VRF_PROBLEM_AREA >> 2;

// VRF DAO
uint256 constant VRF_RECORD_STORAGE_FEE = 100000;

/**
 * This limit rate increments max_records_x_campaign for reputation earnings.
 */
uint32 constant VRF_CAMPAIGN_RECORDS_LIMIT_RATE = 8;
uint32 constant VRF_MAX_CAMPAIGN_RECORDS_X_ISLAND = 6;

uint constant VRF_GATHEING_SIGNED_SOLUTIONS_INTERVAL = 2 hours;
uint constant VRF_GATHEING_REVEALED_SOLUTIONS_INTERVAL = 1 days;

uint256 constant VRF_MIN_AVAILABLE_RECORDS = 8;

// VRF state flags
uint32 constant VRF_RECORD_STATE_AVAILABLE = INVALID_INDEX32;
uint32 constant VRF_RECORD_STATE_REVEALED = VRF_RECORD_STATE_AVAILABLE - 1;
uint32 constant VRF_RECORD_STATE_FAULTED = VRF_RECORD_STATE_AVAILABLE - 2;


library Fix64Math
{
   function mul(int64 val0, int64 val1) public pure returns(int64)
   {
      int128 bignum = int128(val0) * int128(val1);
      return int64(bignum >> DV_FIX64_FRACBITS);
   }

   function div(int64 value, int64 divisor) public pure returns(int64)
   {
      if(divisor == int64(0))
      {
         return DV_FIX64_NAN;
      }

      int128 bignum = int128(value);      
      int128 retval = (bignum << uint128(DV_FIX64_FRACBITS)) / int128(divisor);
      return int64(retval);
   }
}




/**
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

   function get_seed256(PCGSha256RandomState storage pcgstate) internal view returns(uint256)
   {
      uint256 retval = uint256(pcgstate.state0);
      retval |= uint256(pcgstate.state1) << 64;
      retval |= uint256(pcgstate.state2) << 128;
      retval |= uint256(pcgstate.state3) << 192;
      return retval;
   }

   function next_value(PCGSha256RandomState storage pcgstate) internal returns(uint256)
   {
      uint64 _state0 = PCG32RandomLib.advance_state(pcgstate.state0);
      uint32 val00 = PCG32RandomLib.rng_value(_state0);
      _state0 = PCG32RandomLib.advance_state(_state0);
      uint32 val01 = PCG32RandomLib.rng_value(_state0);
      
      uint64 _state1 = PCG32RandomLib.advance_state(pcgstate.state1);
      uint32 val10 = PCG32RandomLib.rng_value(_state1);
      _state1 = PCG32RandomLib.advance_state(_state1);
      uint32 val11 = PCG32RandomLib.rng_value(_state1);
      
      uint64 _state2 = PCG32RandomLib.advance_state(pcgstate.state2);
      uint32 val20 = PCG32RandomLib.rng_value(_state2);
      _state2 = PCG32RandomLib.advance_state(_state2);
      uint32 val21 = PCG32RandomLib.rng_value(_state2);
      
      uint64 _state3 = PCG32RandomLib.advance_state(pcgstate.state3);
      uint32 val30 = PCG32RandomLib.rng_value(_state3);
      _state3 = PCG32RandomLib.advance_state(_state3);
      uint32 val31 = PCG32RandomLib.rng_value(_state3);
      
      pcgstate.state0 = _state2;
      pcgstate.state1 = _state3;
      pcgstate.state2 = _state1;
      pcgstate.state3 = _state0;


      bytes32 retbytes = keccak256(abi.encodePacked(val00, val01, val11, val10, val20, val21, val31, val30));
      return uint256(retbytes);      
   }

}

struct VRFCircle
{
   int64 x;
   int64 y;
   int64 radius;
}

/**
 * Geometric Problem configuration
 */
struct VRFProblem
{
   // Maximum number of circles of the problem. 16 by default
   uint32 max_static_circle_count;

   // current number of circles of the problem. Up to max_static_circle_count
   uint32 static_circle_count;

   
   // Space area size where the circles lie
   int64 problem_area_size;


   // Maximum radius of the generated circles
   int64 max_circle_radius;


   PCGSha256RandomState rnd_generator;
    
   /// Pseudo array
   mapping(uint32 => VRFCircle) static_circles;    
    
}

library VRFProblemLib
{

   // call this on contract constructor
   function init(VRFProblem storage problem, uint256 seed) internal
   {
      problem.max_static_circle_count = VRF_CIRCLES_COUNT;
      problem.static_circle_count = 0;
      problem.problem_area_size = VRF_PROBLEM_AREA;
      problem.max_circle_radius = VRF_PROBLEM_MAXRADIUS;

      PCGSha256RandomLib.configure(problem.rnd_generator, seed);
   }


   // call this when generating a new sequence
   function configure(VRFProblem storage problem, uint256 seed) internal
   {      
      problem.static_circle_count = 0;
      PCGSha256RandomLib.configure(problem.rnd_generator, seed);
   }

   function restart_problem(VRFProblem storage problem) internal
   {
      problem.static_circle_count = 0;
   }

   function create_circle_rnd(VRFCircle storage target_circle, uint256 seed, uint64 problem_area_size, uint64 max_circle_radius) internal
   {
      uint256 mask = 0xffffffffffffffff;
      uint64 u_x = uint64(seed & mask);
      uint64 u_y = uint64((seed >> 64) & mask);
      uint64 u_radius = uint64((seed >> 128) & mask);
      uint64 u_carry = uint64((seed >> 192) & mask);

      u_x = u_x ^ u_carry;
      u_y = u_y ^ PCG32RandomLib.i64_rotate_right(u_carry, 24);
      u_radius = u_radius ^ PCG32RandomLib.i64_rotate_right(u_carry, 48);

      target_circle.x = int64(u_x % problem_area_size);
      target_circle.y = int64(u_y % problem_area_size);
      target_circle.radius= int64(u_radius % max_circle_radius);
   }

   function has_intersections(VRFProblem storage problem, int64 cx, int64 cy, int64 cradius) internal view returns(bool)
   {
      uint32 circle_count = problem.static_circle_count;
      for(uint32 i = 0; i < circle_count; i++)
      {
         VRFCircle storage s_circle = problem.static_circles[i];

         // calculate distance between centers
         int64 diffvec_x = s_circle.x - cx;
         int64 diffvec_y = s_circle.y - cy;
         int64 dist_sqr = Fix64Math.mul(diffvec_x, diffvec_x) + Fix64Math.mul(diffvec_y, diffvec_y);

         // calculate squared sum of radius 
         int64 sumradius = cradius + s_circle.radius;
         int64 sumradius_sqr = Fix64Math.mul(sumradius, sumradius);

         if(sumradius_sqr > dist_sqr)
         {
            // does intersect
            return true;
         }

      }

      return false;
   }

   /**
    * Returns true when finished
    */
   function insert_new_circle(VRFProblem storage problem) internal returns(bool)
   {
      uint32 curr_index = problem.static_circle_count;
      uint32 top_count = problem.max_static_circle_count;
      if(top_count <= curr_index) return true; // finished here
      uint256 next_seed = PCGSha256RandomLib.next_value(problem.rnd_generator);

      VRFCircle storage new_circle = problem.static_circles[curr_index];

      create_circle_rnd(new_circle, next_seed, uint64(problem.problem_area_size), uint64(problem.max_circle_radius));

      bool hascollision = has_intersections(problem, new_circle.x, new_circle.y, new_circle.radius);
      if(hascollision)
      {
         return false;// not ready yet
      }

      // commit new member
      curr_index++;
      problem.static_circle_count = curr_index;

      return curr_index  >= top_count;// has finished
   }
   
}


struct VRFSignedRecord
{
   uint256 island_tokenID;/// Island holds reputation
   
   address pk_owner;/// public key of the owner of the Island   
   
   uint256 campaingID;// Current campaing where this record has been originated
   uint32 island_campaign_index;// index on the current campaign that the island is getting involved
   uint32 island_record_index;// index on the current record belonging to the island

   /**
    * Index of the proposal. Also reveals the state of the record when being played:
    * - VRF_RECORD_STATE_AVAILABLE indicates that this record hasn't been commited for proposals yet.
    * - VRF_RECORD_STATE_REVEALED indicates that this record has been used for random generation.
    * - VRF_RECORD_STATE_FAULTED indicates that this record has been proposed but faulted on the revelation phase.
    */
   uint32 proposal_index;
   bytes signature;// signature of the message
}

enum eVRF_CAMPAIGN_STATUS 
{ 
   /**
    * No campaign has been inserted yet. New records would obtain 
    * the index of the last campaign.
    */
   VRFCAMPAIGN_IDLE,
   VRFCAMPAIGN_PROCESSING_PROBLEM,
   VRFCAMPAIGN_GATHERING_PROPOSALS,
   VRFCAMPAIGN_GATHERING_REVEALS,
   VRFCAMPAIGN_CLOSING
}

struct VRFIslandInfo
{
   /**
    * This Reputation score increments each time that the Island completes a reveal correctly.
    * In case of providing wrong information or failing to reveal its commited response, this score
    * is set to 0  and the Island get banned permanently. 
    */
   uint32 reputation;


   /**
    * Bonus credits for keep playing. This bonus could get earned when an
    * Island helps with the processing of the problem configuration, or
    * when helps with the termination of the campaign.
    */ 
   uint32 bonus_credits;

   /**
    * Maximum allowed signed records that an Island could submit during a campaign
    */
   uint32 max_records_x_campaign;

   /// Last campaign where this Island has inserted signed records
   uint256 last_campaingID;

   /// index on the current record belonging to the island
   uint32 last_record_index;


   /// Index in signed_records_x_island collection where the available records could be counted
   /// Starts with 0 and increments succesively
   uint32 available_record_listing_index;


   /// current proposal record. 0 If not proposal yet
   uint256 current_proposal;

   /**
    * Paid balance from bounties
    */
   uint256 bounty_balance;
}


struct VRFCampaignTask
{
   uint256 campaingID;
   /**
    * The client task ID which is notified when a new random number is generated.
    * This number could mean a target Island which needs a random seed for ring generation,
    * Or also it could tell the random seed for a Propomtion Lottery.
    */
   uint256 task_refID;
   /**
    * IF bounty is 0, then this problem has already solved
    */
   uint256 bounty;

   /// Generated random seed
   uint256 random_seed;
}

struct VRFLeadboard
{
   /// First place leadboard record. 0 if not assigned yet
   uint256 first_place;
   /// second place leadboard record. 0 if not assigned yet
   uint256 second_place;

   /// third place leadboard record. 0 if not assigned yet
   uint256 third_place;


   /**
    * Last winner island ID
    */
   uint256 last_winner;

   VRFCircle first_circle;
   VRFCircle second_circle;
   VRFCircle third_circle;
}

/**
 *
 */
struct VRFDAOState
{ 

   eVRF_CAMPAIGN_STATUS process_status;

   /**
    * A consecutive index. Starts with 1. 0 Means no campaign has been initiated.
    * Tells the current campaign to be resolved with random number generation.
    */ 
   uint256 current_campaingID;


   /**
    * This value is always incrementing. Each time tells the newly created campaign when a task is inserted  
    */
   uint256 campaing_count;


   /**
    * A consecutive index for records. Starts with 1.
    */ 
   uint256 current_recordID;

   /**
    * Storage fee for creating a new record. 
    * Records created during a processing phase don't have to pay a fee.
    */
   uint256 record_storage_fee;

   /**
    * Records not spend yet
    */
   uint256 available_records;

   /**
    * Accumulated fees during the last campaign. It will be grant to the winner
    */
   uint256 accumulated_fee_bounty;

   uint gathering_signed_solutions_interval;
   uint gathering_revealed_solutions_interval;
   uint phase_due_time;/// Due time to the next phase
   /// Maximum number of proposals for campaign
   uint32 max_campaign_proposals;

   /**
    *  By default VRF_MIN_AVAILABLE_RECORDS
    */
   uint32 minimum_records_for_campaign;
   /**
    * Current puzzle problem
    */
   VRFProblem problem;


   mapping(uint256 => VRFIslandInfo) islands_info;
   

   /**
    * A one-based Array set which matchs the campaign ID with the task information
    */
   mapping(uint256 => VRFCampaignTask) campaign_tasks;


   /**
    * A one-based Array set which matchs the Island VRF record ID with the record information
    */
   mapping(uint256 => VRFSignedRecord) signed_records;

   /**
    * Records relationship with Islands
    */
   DVOwnershipArray signed_records_x_island;



   /**
    * Proposals are identifiers to signed records
    */
   DVStackArray proposals;

   VRFLeadboard leadboard;
   
}


library VRFDAOLib
{
   function reset_leader_board(VRFLeadboard storage leadboard) internal
   {
      leadboard.first_place = 0;
      leadboard.second_place = 0;
      leadboard.third_place = 0;
   }

   function lb_move_first_to_second(VRFLeadboard storage leadboard) internal
   {
      leadboard.third_place = leadboard.second_place;
      leadboard.third_circle.x = leadboard.second_circle.x;
      leadboard.third_circle.y = leadboard.second_circle.y;
      leadboard.third_circle.radius = leadboard.second_circle.radius;

      leadboard.second_place = leadboard.first_place;
      leadboard.second_circle.x = leadboard.first_circle.x;
      leadboard.second_circle.y = leadboard.first_circle.y;
      leadboard.second_circle.radius = leadboard.first_circle.radius;
   }


   function lb_move_second_to_third(VRFLeadboard storage leadboard) internal
   {
      leadboard.third_place = leadboard.second_place;
      leadboard.third_circle.x = leadboard.second_circle.x;
      leadboard.third_circle.y = leadboard.second_circle.y;
      leadboard.third_circle.radius = leadboard.second_circle.radius;
   }

   function insert_lb_candidate(VRFLeadboard storage leadboard, uint256 record_candidate, int64 radius, int64 cx, int64 cy) internal returns(bool)
   {
      if(leadboard.first_place == 0)
      {
         leadboard.first_place = record_candidate;
         leadboard.first_circle.x = cx;
         leadboard.first_circle.y = cy;
         leadboard.first_circle.radius = radius;
         return true;
      }

      if(leadboard.first_circle.radius < radius)
      {
         // its a winner
         lb_move_first_to_second(leadboard);
         leadboard.first_place = record_candidate;
         leadboard.first_circle.x = cx;
         leadboard.first_circle.y = cy;
         leadboard.first_circle.radius = radius;
         return true;
      }

      if(leadboard.second_place == 0)
      {
         leadboard.second_place = record_candidate;
         leadboard.second_circle.x = cx;
         leadboard.second_circle.y = cy;
         leadboard.second_circle.radius = radius;
         return true;
      }
      else if(leadboard.second_circle.radius < radius) 
      {
         lb_move_second_to_third(leadboard);
         leadboard.second_place = record_candidate;
         leadboard.second_circle.x = cx;
         leadboard.second_circle.y = cy;
         leadboard.second_circle.radius = radius;
         return true;
      }


      if(leadboard.third_place == 0 || leadboard.third_circle.radius < radius)
      {
         leadboard.third_place = record_candidate;
         leadboard.third_circle.x = cx;
         leadboard.third_circle.y = cy;
         leadboard.third_circle.radius = radius;
         return true;
      }

      return false;
   }

   function get_last_seed(VRFDAOState storage daostate) internal view returns(uint256)
   {
      return PCGSha256RandomLib.get_seed256(daostate.problem.rnd_generator);
   }

   function next_rnd_number(VRFDAOState storage daostate) internal returns(uint256)
   {
      return PCGSha256RandomLib.next_value(daostate.problem.rnd_generator);
   }

   /**
    * This function resets leadboard and configures rnd_generator.
    * Cancels operation if the leadboard hasn't been prepared properly
    */
   function configure_new_seed_rnd(VRFDAOState storage daostate) internal
   {
      uint256 first_place = daostate.leadboard.first_place;
      require(first_place != 0, "A winner is needed for generating new random sequences.");
      int64 cx1 = daostate.leadboard.first_circle.x;
      int64 cy1 = daostate.leadboard.first_circle.y;
      int64 radius1 = daostate.leadboard.first_circle.radius;

      uint256 base_rnd = next_rnd_number(daostate);

      uint256 new_seed = 0;

      uint256 second_place = daostate.leadboard.second_place;
      if(second_place == 0)
      {
         // calculate random with only the winner
         bytes32 retbytes00 = keccak256(abi.encode(base_rnd, first_place));
         bytes32 retbytes01 = keccak256(abi.encode(cx1, cy1, radius1));
         new_seed = uint256(keccak256(abi.encodePacked(retbytes00, retbytes01)));
      }
      else
      {
         int64 cx2 = daostate.leadboard.second_circle.x;
         int64 cy2 = daostate.leadboard.second_circle.y;
         int64 radius2 = daostate.leadboard.second_circle.radius;

         uint256 third_place = daostate.leadboard.third_place;
         if(third_place == 0)
         {
            bytes32 retbytes10 = keccak256(abi.encode(base_rnd, first_place, second_place));
            bytes32 retbytes11 = keccak256(abi.encode(cx1, cy1, radius1));
            bytes32 retbytes12 = keccak256(abi.encode(cx2, cy2, radius2));
            new_seed = uint256(keccak256(abi.encodePacked(retbytes10, retbytes11, retbytes12)));
         }
         else
         {
            int64 cx3 = daostate.leadboard.third_circle.x;
            int64 cy3 = daostate.leadboard.third_circle.y;
            int64 radius3 = daostate.leadboard.third_circle.radius;

            bytes32 retbytes20 = keccak256(abi.encode(base_rnd, first_place, second_place, third_place));
            bytes32 retbytes21 = keccak256(abi.encode(cx1, cy1, radius1));
            bytes32 retbytes22 = keccak256(abi.encode(cx2, cy2, radius2));
            bytes32 retbytes23 = keccak256(abi.encode(cx3, cy3, radius3));
            new_seed = uint256(keccak256(abi.encodePacked(retbytes20, retbytes21, retbytes22, retbytes23)));
         }
      }
      
      // configure new seed
      VRFProblemLib.configure(daostate.problem, new_seed);
      reset_leader_board(daostate.leadboard);
   }
   
   function could_start_campaign(VRFDAOState storage daostate) internal view returns(bool)
   {
      if(daostate.campaing_count == 0) return false;
      if(daostate.current_campaingID >= daostate.campaing_count) return false;

      if(daostate.available_records < uint256(daostate.minimum_records_for_campaign)) return false;
      return true;
   }

   // resets current campaign with the same time frame and a new random sequence
   function reset_campaign(VRFDAOState storage daostate) internal
   {
      daostate.process_status = eVRF_CAMPAIGN_STATUS.VRFCAMPAIGN_PROCESSING_PROBLEM;
      VRFProblemLib.restart_problem(daostate.problem);
   }

   function check_campaign_phase(VRFDAOState storage daostate, uint blocktime) internal
   {
      // If this DAO is idle, start problem solving
      if(daostate.process_status == eVRF_CAMPAIGN_STATUS.VRFCAMPAIGN_IDLE)
      {
         // could start a new campaign.
         if(could_start_campaign(daostate))
         {
            if(daostate.current_campaingID > 0)
            {
               // advance to the problem solving phase
               daostate.current_campaingID++;
               daostate.process_status = eVRF_CAMPAIGN_STATUS.VRFCAMPAIGN_PROCESSING_PROBLEM;
            }
         }
      }
      else if(daostate.process_status == eVRF_CAMPAIGN_STATUS.VRFCAMPAIGN_GATHERING_PROPOSALS)
      {
         if(blocktime > daostate.phase_due_time)
         {
            // check ammount of proposals
            if(daostate.proposals.count == 0)
            {
               // restart campaign.
               reset_campaign(daostate);
            }
            else 
            {
               // move to the next phase for reveals
               daostate.process_status = eVRF_CAMPAIGN_STATUS.VRFCAMPAIGN_GATHERING_REVEALS;
               daostate.phase_due_time = blocktime + daostate.gathering_revealed_solutions_interval;
            }
         }
      }
      else if(daostate.process_status == eVRF_CAMPAIGN_STATUS.VRFCAMPAIGN_GATHERING_REVEALS)
      {
         if(blocktime > daostate.phase_due_time)
         {
            // mark the finalization phase
            daostate.process_status = eVRF_CAMPAIGN_STATUS.VRFCAMPAIGN_CLOSING;
         }
      }
   }

   function insert_task(VRFDAOState storage daostate, uint blocktime,
                        uint256 task_refID, uint256 bounty) internal returns(uint256)
   {
      uint256 oldcount = daostate.campaing_count;
      uint256 new_campaignID = oldcount + 1;
      daostate.campaing_count = oldcount + 1;

      daostate.campaign_tasks[new_campaignID].campaingID = new_campaignID;
      daostate.campaign_tasks[new_campaignID].task_refID = task_refID;
      daostate.campaign_tasks[new_campaignID].bounty = bounty;
      

      // If this DAO is idle, start problem solving
      check_campaign_phase(daostate, blocktime);
      return new_campaignID;
   }
   
   

   function calc_record_params_hash(uint256 campaingID, uint32 island_campaign_index, int64 cx, int64 cy, int64 radius) internal pure returns(bytes32)
   {
      return keccak256(abi.encodePacked(campaingID, island_campaign_index, cx,  cy, radius));
   }

   function is_valid_record_signature(VRFDAOState storage daostate, uint256 recordID, address pk_owner, int64 cx, int64 cy, int64 radius) internal view returns(bool)
   {
      VRFSignedRecord storage record = daostate.signed_records[recordID];

      uint256 campaingID = record.campaingID;
      if(campaingID == 0)
      {
         return false;// record not assigned yet
      }

      if(record.pk_owner != pk_owner) return false;

      
      uint32 island_campaign_index = record.island_campaign_index;

      bytes32 chash = calc_record_params_hash(campaingID, island_campaign_index, cx, cy, radius);
      bytes32 eth_digest = ECDSA.toEthSignedMessageHash(chash);// adapt to Ethereum signature format

      (address recovered, ECDSA.RecoverError error) = ECDSA.tryRecover(eth_digest, record.signature);

      if (error == ECDSA.RecoverError.NoError && recovered == pk_owner) {
         return true;
      }

      return false;
   }


   /**
    * This method needs to be called by client before attempting to insert new signed records on current campaign.
    * Returns the campaign ID and the index for the next record.
    * If island_tokenID is not allowed to register more records, it returns (0, INVALID_INDEX32)
    */
   function suggested_record_indexparams(VRFDAOState storage daostate, uint256 island_tokenID) internal view returns(uint256, uint32)
   {
      VRFIslandInfo storage fetch_island = daostate.islands_info[island_tokenID];
      
      if(fetch_island.reputation < 1)
      {
         return (0, INVALID_INDEX32);
      }

      uint256 current_campaign = daostate.current_campaingID;
      uint256 last_campaign_ref = fetch_island.last_campaingID;
      
      if(last_campaign_ref < current_campaign) // || last_campaign_ref == 0
      {
         // return current campaign with index 0
         return (current_campaign, 0);
      }

      // Island has been already in this campaign

      /// Check Island record limit      
      uint32 next_index = fetch_island.last_record_index + 1;
      if(fetch_island.max_records_x_campaign <= next_index)
      {
         // reached limit
         return (0, INVALID_INDEX32);
      }

      return (current_campaign, next_index);
   }

   /**
    * signature must sign
    */
   function insert_signed_record_base(VRFDAOState storage daostate,
                                      uint256 island_tokenID,
                                      address pk_owner,
                                      bytes calldata signature) internal returns(uint256, bool)
   {

      VRFIslandInfo storage fetch_island = daostate.islands_info[island_tokenID];
      if(fetch_island.reputation < 1)
      {
         return (0, false);
      }

      uint256 current_campaign = daostate.current_campaingID;

      uint256 last_campaign_ref = fetch_island.last_campaingID;
      uint32 next_index = 0;
      
      if(last_campaign_ref == current_campaign) // element has been already in this campaign
      {
         // update index
         next_index = fetch_island.last_record_index + 1;        

         /// Check Island record limit      
         if(fetch_island.max_records_x_campaign <= next_index)
         {
            // reached limit
            return (0, false);
         }
      }

      // increment record index
      daostate.current_recordID++;
      uint256 newrecordID = daostate.current_recordID;

      VRFSignedRecord storage newrecord_obj = daostate.signed_records[newrecordID];

      newrecord_obj.island_tokenID = island_tokenID;
      newrecord_obj.pk_owner = pk_owner;
      newrecord_obj.campaingID = current_campaign;
      newrecord_obj.island_campaign_index = next_index;
      newrecord_obj.proposal_index = VRF_RECORD_STATE_AVAILABLE;
      newrecord_obj.signature = signature;

      // reference newly created record campaign on Island
      fetch_island.last_campaingID = current_campaign;
      fetch_island.last_record_index = next_index;

      // Reference in the Island inventory
      newrecord_obj.island_record_index = DVOwnershipArrayUtil.insert(daostate.signed_records_x_island, island_tokenID, newrecordID);

      // increment record inventory
      daostate.available_records++;

      return (newrecordID, true);
   }

   function insert_record_payable(VRFDAOState storage daostate,
                                  uint blocktime, // for calculating expiration time
                                  uint256 island_tokenID,                                  
                                  address pk_owner,
                                  uint256 fee,
                                  bytes calldata signature) internal returns(uint256)
   {
      require(fee >= daostate.record_storage_fee, "Not enough paid for storage");
      (uint256 newrecordID, bool success) = insert_signed_record_base(daostate, island_tokenID, pk_owner, signature);
      require(success == true, "Cannot produce more records for this Island");
      daostate.accumulated_fee_bounty += fee;

      // attempt to initiate problem solving phase if idle
      check_campaign_phase(daostate, blocktime);
      return newrecordID;
   }

   /**
    * Calling this method contributes to the problem processing.
    * By calling this method, the state of the DAO could transition to the VRFCAMPAIGN_GATHERING_PROPOSALS phase.
    * That's why this needs the blocktime for calculating the expiration time
    */
   function insert_record_problem_working(VRFDAOState storage daostate,
                                          uint blocktime, // for calculating expiration time
                                          uint256 island_tokenID,
                                          address pk_owner,
                                          bytes calldata signature) internal returns(uint256)
   {  
      require(daostate.process_status == eVRF_CAMPAIGN_STATUS.VRFCAMPAIGN_PROCESSING_PROBLEM, "Cannot get the benefit of problem solving bonus");

      (uint256 newrecordID, bool success) = insert_signed_record_base(daostate, island_tokenID, pk_owner, signature);
      require(success == true, "Cannot produce more records for this Island");


      // contribute to the problem solving
      bool hasfinished = VRFProblemLib.insert_new_circle(daostate.problem);
      if(hasfinished)
      {
         // move to gathering process
         daostate.process_status = eVRF_CAMPAIGN_STATUS.VRFCAMPAIGN_GATHERING_PROPOSALS;
         // calculation the expiration time
         daostate.phase_due_time = blocktime + daostate.gathering_signed_solutions_interval;
      }
      
      // earn a bonus
      VRFIslandInfo storage fetch_island = daostate.islands_info[island_tokenID];
      fetch_island.bonus_credits++;

      return newrecordID;
   }

   /**
    * Insert record without paying fee, but bonus
    */
   function insert_record_by_bonus(VRFDAOState storage daostate, 
                                    uint blocktime, // for calculating expiration time
                                    uint256 island_tokenID, address pk_owner,
                                    bytes calldata signature) internal returns(uint256)
   {
      VRFIslandInfo storage fetch_island = daostate.islands_info[island_tokenID];
      uint256 bonus = fetch_island.bonus_credits;  
      require(bonus > 0, "Not allowed to use bonus on record signatures");
      (uint256 newrecordID, bool success) = insert_signed_record_base(daostate, island_tokenID, pk_owner, signature);
      require(success == true, "Cannot produce more records for this Island");
      
      fetch_island.bonus_credits--;

      // attempt to initiate problem solving phase if idle
      check_campaign_phase(daostate, blocktime);
      return newrecordID;
   }

   /**
    * This function must be called when creating an Island from the main contract
    */
   function register_island(VRFDAOState storage daostate, uint256 island_tokenID) internal
   {
      VRFIslandInfo storage fetch_island = daostate.islands_info[island_tokenID];
      
      // Every Island starts with a base reputation. If faulted, it sets to 0,
      fetch_island.reputation = 1;
      fetch_island.bonus_credits = 0;
      fetch_island.max_records_x_campaign = 1;
      fetch_island.last_campaingID = 0;
      fetch_island.last_record_index = 0;
      fetch_island.available_record_listing_index = 0;
      fetch_island.current_proposal = 0;
      fetch_island.bounty_balance = 0;
   }

   function make_proposal(VRFDAOState storage daostate, address pk_owner, uint blocktime) internal
   {

   }

   /**
    * This is called on revelations
    */
   function remove_proposal(VRFDAOState storage daostate, uint32 index, bool revealed_success) internal
   {
      assert(index < daostate.proposals.count);

      uint256 removed_recordID = DVStackArrayUtil.get(daostate.proposals, index);
      daostate.signed_records[removed_recordID].proposal_index = revealed_success ? VRF_RECORD_STATE_REVEALED : VRF_RECORD_STATE_FAULTED;


      (uint32 last_index, bool success) = DVStackArrayUtil.remove(daostate.proposals, index);
      assert(success == true);
      if(last_index != index)
      {
         // change index on target
         uint256 moved_recordID = DVStackArrayUtil.get(daostate.proposals, index);
         daostate.signed_records[moved_recordID].proposal_index = index;
      }
   }


}
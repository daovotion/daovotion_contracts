//SPDX-License-Identifier:MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "./DVList.sol";


uint constant DV_PERCENTAJE_FACTOR = 10000;
uint constant DV_MAX_COMMISSION_PERCENTAJE = 9000;
uint constant DV_MAX_INSURANCE_PERCENTAJE = 5000;


uint constant DV_DEFAULT_TOKEN_ID = 1; // A reference value that is not used and could indicates a null.

// Prestige Degree Levels
//
uint16 constant DV_WOODEN_DEGREE = 0;
uint16 constant DV_BRONZE_DEGREE = 1;
uint16 constant DV_SILVER_DEGREE = 2;
uint16 constant DV_GOLDEN_DEGREE = 3;
uint16 constant DV_DIAMOND_DEGREE = 4;
//

// Prestige Graduation degree
//
uint32 constant DV_BRONZE_GRADUATION = 6;
uint32 constant DV_SILVER_GRADUATION = 9;

uint32 constant DV_BRONZE_GRAPE_INIT = 3;
uint32 constant DV_SILVER_GRAPE_INIT = 3;
uint32 constant DV_GOLDEN_GRAPE_INIT = 5;
uint32 constant DV_DIAMOND_GRAPE_INIT = 5;
//

// Egregore promotion status
//
int16 constant DV_STATUS_UNACCREDITED = 0;
int16 constant DV_STATUS_GUILTY = -1;
int16 constant DV_STATUS_ACCREDITED = 1;
int16 constant DV_STATUS_SPONSORSHIP_BONUS = 2;
int16 constant DV_STATUS_HONORABLE_BONUS = 4;
int16 constant DV_STATUS_HONORABLE_SPONSOR_BONUS = 7;
int16 constant DV_STATUS_SPONSORSHIP_EXTRA_BONUS = 8;
//



// Token types
//
uint256 constant DV_SEED_TOKEN = 1;
uint256 constant DV_EGREGORE_TOKEN = 2;
uint256 constant DV_DEVOTEE_TOKEN = 3;
uint256 constant DV_PUZZLE_TOKEN = 4;
uint256 constant DV_BULL_TOKEN = 5;
uint256 constant DV_ARCHANGEL_TOKEN = 6;
///


// Prestige promotion status
//




struct EgregoreMeta
{
    string name;
    /// URL of the official web site for the project
    string projectURL;
    string description;    
}


struct EgregorePrestige
{
    /**
     * Indicates how this Egregore would be promoted. Also indicates if it is
     * unaccredited or if it has its reputation damaged, with the following values:
     * 
     * - DV_STATUS_UNACCREDITED
     * - DV_STATUS_GUILTY
     * - DV_STATUS_ACCREDITED
     * - DV_STATUS_SPONSORSHIP_BONUS
     * - DV_STATUS_HONORABLE_BONUS
     * - DV_STATUS_HONORABLE_SPONSOR_BONUS
     * - DV_STATUS_SPONSORSHIP_EXTRA_BONUS
     */
    int16 promotion_status;

    /**
     * Prestige Degree Level:
     * 
     * - DV_WOODEN_DEGREE
     * - DV_BRONZE_DEGREE
     * - DV_SILVER_DEGREE
     * - DV_GOLDEN_DEGREE
     * - DV_DIAMOND_DEGREE
     */
    uint16 degree;

    /// Prestige grace periods
    uint32 grace_grapes;

    /**
     * Punishment periods after declared guilty. Until a certain number of periods passed,
     * this Egregore gets downgrade by losing 1 grace grape.
     */
    uint32 punsishment_periods;
}

/**
 * Price parameters for devotees and commissions distribution
 */
struct EgregorePricing
{
    uint256 floor_price;
    
    /// Mimium flat commission fee added to the price, before taxes.
    uint256 minimum_commission; 
    
    /// total commision before taxes, calculated on selling price.
    /// If 0, commission will be the diference between selling price and floor price
    uint256 commission_rate;

    /// Insurance tax percentaje, calculated over raw commission before taxes.
    uint256 insurance_rate;

    /**
     * Percentaje of the insurance pool that can be compromised. 
     * So when the defaulted obligations surpass this threshold,
     * it triggers a global downpaynebt to the insurance vault
     * where all members from the entire Egregore organization will be charged
     * during this period by losing their commissions.
     */
    uint256 insurance_risk_threshold;

    /**
     * Threshold of Devotees referring sales that has to achive this devotee to becomming a Master Biship.
     * This is stablished by the Egregore.
     */
    uint graduation_threshold;
}


struct EgregoreDevoteeMinting
{
    uint founder_reserve;
    uint initial_mint_count;
}

struct EgregoreBudget
{
    /**
     * Current Egregore Treasure Balance, which hasn't been liquidate yet.
     * 
     */
    uint256 egregore_treasure_vault;
    
    /**
     * Accumulated project payout to project maintainers. which has been substracted from  egregore_treasure_vault
     */
    uint256 project_payout_amount;

    /// total funds collected for insurance
    uint256 insurance_vault; 

    /// total commision after taxes
    uint256 accumulated_commissions;
    
    /**
     * Accumulated reserve for taxes. It should 
     * reach minimum_tax_per_period for being processed 
     * at the current period.
     * If this Egregore remains unaccredited, the accummulated commissions
     * will be collected only for taxes.
     */
    uint256 tax_reserve;

    
    /// Is this Egregore declared worthy for this period
    bool is_worthy;
}

/// Declared macros
///

function DV_PERCENTAJE(uint256 _price, uint256 _percentaje) pure returns(uint256)
{
    return (_price * _percentaje) /  DV_PERCENTAJE_FACTOR;
}

function DV_MIN_PRICE(EgregorePrestige storage _eginfo)  pure returns(uint256)
{
    return _eginfo.floor_price + _eginfo.minimum_commission;
} 


function DV_ADDRtoU256(address _address)  pure returns(uint256)
{
    return uint256(uint160(_address));
}

function DV_U256toADDR(uint256 _address)  pure returns(address)
{
    return address(uint160(_address));
}


///



library EgregoreCalc
{
    function minimum_price(EgregorePricing storage eginfo) internal pure returns(uint256)
    {
        return eginfo.floor_price + eginfo.minimum_commission;
    }

    function percentaje(uint256 selling_price, uint256 percentaje) internal pure returns(uint256)
    {
        return  (selling_price * percentaje) /  DV_PERCENTAJE_FACTOR;
    }

    /**
    Calculate the commission over price before taxes.
    This assummes that selling_price is greater of equal than minimum price
     */
    function raw_commision(EgregorePricing storage eginfo, uint256 selling_price) internal pure returns(uint256)
    {
        uint256 mincommission = eginfo.minimum_commission;
        uint256 floorprice = eginfo.floor_price;
        uint256 minprice = floorprice + mincommission;
        if(selling_price <= minprice)
        {
            return mincommission;
        }
        else if(eginfo.commission_rate > 0)
        {
            // calculate percentaje for commission derived from the selling price
            uint256 factor_commission = (selling_price * eginfo.commission_rate) /  DV_PERCENTAJE_FACTOR;
            // how much funds left for the Egregore project?
            uint256 collected_funds_base = selling_price - factor_commission;
            
            if(collected_funds_base < floorprice || factor_commission < mincommission)
            {
                return mincommission;
            }

            return factor_commission;            
        }

        return selling_price - floorprice;
    }

    /**
     PrestigeScore = Pow(GraceGrapes,Degree)
     */
    function prestige_score(EgregorePrestige storage eginfo) internal pure returns(uint256)
    {
        uint16 _degree = eginfo.degree;
        if(_degree == DV_WOODEN_DEGREE) return 1;
        uint256 _grapes = uint256(eginfo.grace_grapes);
        if(_degree == DV_BRONZE_DEGREE) return _grapes;
        _grapes *= _grapes;
        if(_degree == DV_SILVER_DEGREE) return _grapes;
        _grapes *= _grapes;
        if(_degree == DV_GOLDEN_DEGREE) return _grapes;
        return _grapes*_grapes;
    }

    /**
     * Promote prestige after a grace period.
     * returns true if this egregore gets promoted to the next level
     */
    function promote_prestige(EgregorePrestige storage eginfo) internal returns(bool)
    {
        int16 _status = eginfo.promotion_status;
        uint16 _degree = eginfo.degree;
        if( _status == DV_STATUS_GUILTY ||
            _status == DV_STATUS_UNACCREDITED ||
            _degree == DV_WOODEN_DEGREE) return false;

        uint32 _grapes = _status & DV_STATUS_ACCREDITED;
        _grapes +=  (_status & DV_STATUS_SPONSORSHIP_BONUS) >> 1;
        _grapes +=  (_status & DV_STATUS_HONORABLE_BONUS) >> 2;
        _grapes +=  (_status & DV_STATUS_SPONSORSHIP_EXTRA_BONUS) >> 3;
        eginfo.grace_grapes += _grapes;

        _grapes = eginfo.grace_grapes;
        

        if(_degree == DV_BRONZE_DEGREE && _grapes >= DV_BRONZE_GRADUATION)
        {
            eginfo.degree = DV_SILVER_DEGREE;
            eginfo.grace_grapes = DV_SILVER_GRAPE_INIT;
        }
        else if(_degree == DV_SILVER_DEGREE && _grapes >= DV_SILVER_GRADUATION)
        {
            eginfo.degree = DV_GOLDEN_DEGREE;
            eginfo.grace_grapes = DV_GOLDEN_GRAPE_INIT;
        }
        else
        {
            return false;
        }

        return true;
    }

    /**
     * Downgrades the egregore if reaches to zero grace grapes.
     * returns true if this egregore gets downgraded to an inferior level
     */
    function punish_egregore(EgregorePrestige storage eginfo, uint32 grapes_payout) internal returns(bool)
    {
        uint16 _degree = eginfo.degree;
        if(_degree == DV_WOODEN_DEGREE) return false; // An unaccredited egregore cannot be punished

        if(eginfo.grace_grapes > grapes_payout)
        {
            // just decrement
            eginfo.grace_grapes -= grapes_payout;
            return false;
        }

        // downgrade
        
        if(_degree == DV_BRONZE_DEGREE)
        {
            // exclude accredited 
            eginfo.degree = DV_WOODEN_DEGREE;
            eginfo.grace_grapes = 0;
            eginfo.promotion_status = DV_STATUS_UNACCREDITED;
        }
        else if(_degree == DV_SILVER_DEGREE)
        {            
            eginfo.degree = DV_BRONZE_DEGREE;
            eginfo.grace_grapes = DV_BRONZE_GRAPE_INIT;
        }
        else if(_degree == DV_GOLDEN_DEGREE)
        {
            
            eginfo.degree = DV_SILVER_DEGREE;
            eginfo.grace_grapes = DV_SILVER_GRAPE_INIT;
        }
        else if(_degree == DV_DIAMOND_DEGREE)
        {
            
            eginfo.degree = DV_GOLDEN_DEGREE;
            eginfo.grace_grapes = DV_GOLDEN_GRAPE_INIT;
        }        

        return true;
    }
}

/**
 * Egregore Descriptive information
 * @remarks Within DAOVOTION contract, Egregore fields are represented different, as sparsed mapping hash tables.
 */
struct EgregoreInfo
{
    /// Id of this Devotee Token
    uint256 egregoreID;

    /// Owner Wallet that controls this Devotee
    /**
     * @remarks If 0, then this Egregore is not longer controlled by its owner, 
       but instead it has an stablished governance where its devotee members have voting power
       on deciding how to distribute funds and change parameters-
       By default, this receiver_wallet should be assigned to the Owner.
     */
    address owner_address;

    
    /**
     * Sponsor Egregore.
     */
    uint256 sponsor_egregoreID;

    /// Name of the project
    string name;
    /// URL of the official web site for the project
    string projectURL;
    string description;

    /// Foundational parameters for emitting Devotee Tokens
    ///
    uint founder_token_reserve;
    uint initial_mint_count;
    ///

    /// Base price on Devotee token sale
    uint256 floor_price;
    
    /// Mimium flat commission fee added to the price, before taxes.
    uint256 minimum_commission; 

    /**
     * Total commision before taxes, calculated on selling price.
     * If 0, commission will be the diference between selling price and floor price
     */
    uint256 commission_rate;

    /// Insurance tax percentaje, calculated over raw commission before taxes.
    uint256 insurance_rate;


    /**
     * Percentaje of the insurance pool that can be compromised. 
     * So when the defaulted obligations surpass this threshold,
     * it triggers a global downpaynebt to the insurance vault
     * where all members from the entire Egregore organization will be charged
     * during this period by losing their commissions.
     */
    uint256 insurance_risk_threshold;
    
    /**
     * Threshold of Devotees referring sales that has to achive this devotee to becomming a Master Biship.
     * This is stablished by the Egregore.
     */
    uint graduation_threshold;

    /**
     * Current Egregore Treasure Balance, which hasn't been liquidate yet.
     * 
     */
    uint256 egregore_treasure_vault;
    
    /**
     * Accumulated project payout to project maintainers. which has been substracted from  egregore_treasure_vault
     */
    uint256 project_payout_amount;

    /// total funds collected for insurance
    uint256 insurance_vault; 

    /// total commision after taxes
    uint256 accumulated_commissions;
    
    /**
     * Accumulated reserve for taxes. It should 
     * reach minimum_tax_per_period for being processed 
     * at the current period.
     * If this Egregore remains unaccredited, the accummulated commissions
     * will be collected only for taxes.
     */
    uint256 tax_reserve;

    
    /// Is this Egregore declared worthy for this period
    bool is_worthy;


    

    /**
     * Indicates how this Egregore would be promoted. Also indicates if it is
     * unaccredited or if it has its reputation damaged, with the following values:
     * 
     * - DV_STATUS_UNACCREDITED
     * - DV_STATUS_GUILTY
     * - DV_STATUS_ACCREDITED
     * - DV_STATUS_SPONSORSHIP_BONUS
     * - DV_STATUS_HONORABLE_BONUS
     * - DV_STATUS_HONORABLE_SPONSOR_BONUS
     */
    int16 promotion_status;

    /**
     * Prestige Degree Level:
     * 
     * - DV_WOODEN_DEGREE
     * - DV_BRONZE_DEGREE
     * - DV_SILVER_DEGREE
     * - DV_GOLDEN_DEGREE
     * - DV_DIAMOND_DEGREE
     */
    uint16 degree;

    /// Prestige grace periods
    uint32 grace_grapes;

    /**
     * Punishment periods after declared guilty. Until a certain number of periods passed,
     * this Egregore gets downgrade by losing 1 grace grape.
     */
    uint32 punsishment_periods;

    /// Calculated prestige score
    uint256 prestige_score;


    /// Devotee listing
    uint devotee_count;
    uint256 devotee_list_head;
    
}

/**
    Devotee descriptive information
    @remarks Within DAOVOTION contract, devotees fields are represented different, as sparsed mapping hash tables.
 */
struct DevoteeInfo
{
    /// Id of this Devotee Token
    uint256 devoteeID;

    /// Organization which this Devotee belongs to,
    uint256 egregoreID;
    
    /**
     * Owner Wallet that controls this Devotee.
     * When a Devotee faulted to its obligations
     */
    address owner_address;

    /// Receiver account that will collect the commmission payments.
    address receiver_wallet;

    /// Reference to a Bishop Devotee. 0 if it has not parent, which defines this devotee as Bishop.
    /**
     * The master bishop established an obligation on its subordinate, the deacon devotee, which belongs to 
     * the master's downline and has to pay tribute from commissions.     
     */ 
    uint256 master_bishop;
        
    /**
     * Seller that offered this new devotee. Could be the same Bishop, or a Deacon. 0 if it is foundational member.
     */
    uint256 referrer; 

    /**
     * Percentaje of tribute that the Deacon Devotee has to pay for its related Bishop master, from the 
     * commissions after taxes. This is stablished by the master bishop.
     * If this devotee is bishop (having 0 in its master_bishop field),
     * then this field tells the commission fee that its subordinates have to pay.
     */
    uint256 bishop_downline_commission_rate;


    /**
     * Accummulated commissions obtained during the Grace period. 
     */
    uint256 accummulated_commissions;



    /**
     * Threshold of Devotees referring sales that has to achive this devotee to becomming a Master Biship.
     * This is stablished by the Egregore.
     */
    uint graduation_threshold;

    /**
     * Number of sales when recruiting new members for the Egregore, as they become devotees.
     * If client_count reaches the graduation_threshold, this devotee becomes a bishop.
     * @remarks Each time a deacon devotee realizes a sale, the client_count increments both
     *  the subordinated Deacon but also on the parent Biship master.
     *  From 
     */
    uint client_count;


    /// Calculated prestige score, including the Egregore prestige score factor
    uint256 social_capital_score;
}


/**
 * Global attributes in daovotion
 */
struct DAOVOTIONInfo
{
    uint256 global_balance;

    /// Accummulated treasure from taxes. Will be used for promotion lottery
    uint256 global_admin_treasure;

    // Used as the URI for all token types by relying on ID substitution, e.g. https://token-cdn-domain/{id}.json
    string base_uri;
    ///

    ///  ********** Global parameters **************** ///
    ///
    /// Global tax percentaje from commissions (5%)
    uint256 global_tax_rate;


    /**
     * Minimum commissions ammount that an Egregore has to 
     * collect in taxes (~ 5% global tax) in order to be considerd "Worthy",
     * So it could being processed and get promoted during this periods.
     */
    uint256 minimum_tax_per_period;

    /**
     * Number of periods that has to be elapsed before
     * the guilty Egregore has to be punished by losing another grace grape.
     */
    uint32 punishment_periods_before_payout;
    ///

    /// Price for minting seed tokens
    uint256 seed_token_mint_price;

    /// maximum seed token supply
    uint256 seed_token_max_supply;

    /// Current seed token minted
    uint256 seed_token_minted_amount;
}

/**
 * DAOVOTION handles 6 kinds of tokens:
 * - 1 : SEED token. Used for creating Egregores.
 * - 2 : EGREGORE token. Identifies a DAO corporation known as Egregore.
 * - 3 : DEVOTEE token. Identifies a DAO member of an Egregore.
 * - 4 : PUZZLE token. Identifies a puzzle piece for the governance game.
 * - 5 : BULL token. Identifies an advanced puzzle piece for the governance game.
 * - 6 : ARCHANGEL token. Identifies a governance token that are used for promoting Egregores.
 * 
 *  Devotee tokens could being related each other and are intrinsically linked to an Egregore.
 *
 * @dev Implementation of the basic standard multi-token.
 * See https://eips.ethereum.org/EIPS/eip-1155 
 *
 * _Available since v3.1._
 */
contract DAOVOTION is Ownable, ERC165 {
    using Address for address;

    // for lists
    using DVTokenListUtil for DVTokenList;

    using DVTokenOwnershipListUtil for DVTokenOwnershipList;

    event NewEgregoreCreated(address indexed operator, uint256 egregore_id);

    event NewDevoteeMinted(address indexed owner, uint256 egregore_id, uint256 devotee_id, uint256 referrer_id);

    event EgregorePromoted(uint256 egregore_id, uint16 degree);
    
    ///  ********** Global Balance **************** ///
    ///
    /// Global balance
    uint256 private _global_balance;

    /// Accummulated treasure from taxes. Will be used for promotion lottery
    uint256 private _global_admin_treasure;

    
    ///  ********** Global parameters **************** ///
    ///
    /// Global tax percentaje from commissions (5%)
    uint256 private _global_tax_rate;


    /**
     * Minimum commissions ammount that an Egregore has to 
     * collect in taxes (~ 5% global tax) in order to be considerd "Worthy",
     * So it could being processed and get promoted during this periods.
     */
    uint256 private _minimum_tax_per_period;

    /**
     * Number of periods that has to be elapsed before
     * the guilty Egregore has to be punished by losing another grace grape.
     */
    uint32 private _punishment_periods_before_payout;
    ///

    ///  ********** Minting variables **************** ///
    ///
    /// Price for minting seed tokens
    uint256 private _seed_token_mint_price;

    /// maximum seed token supply
    uint256 private _seed_token_max_supply;

    /// Current seed token minted
    uint256 private _seed_token_minted_amount;

    /// Generates egregores consecutives hashes
    uint256 private _egregore_id_gen;
    /// Generates devotees consecutives hashes
    uint256 private _devotee_id_gen;    
    ///

    ///  ********** Fungible tokens for minting Egregores **************** ///
    ///
    /// Balances for fungible seed tokens
    mapping(address => uint256) private _seed_token_balances;
    ///

    ///  ********** Egregore attributes **************** ///
    ///
    // Egregores Info
    mapping(uint256 => EgregoreMeta) private _egregore_meta;

    
    // Egregores pricing
    mapping(uint256 => EgregorePricing) private _egregore_pricing;

    // Egregores prestige
    mapping(uint256 => EgregorePrestige) private _egregore_prestige;

    // Egregores budget
    mapping(uint256 => EgregoreBudget) private _egregore_budget;

    // Egregores minting for Devotees
    mapping(uint256 => EgregoreDevoteeMinting) private _egregore_dev_minting;
    
    // Egregore receiver addresses
    mapping(uint256 => address) private _egregore_receivers;

    // Egregore owner addresses
    mapping(uint256 => address) private _egregore_owners;


    // Egregore sponsors
    mapping(uint256 => uint256) private _egregore_sponsors;

    // Egregores Ownership to addresses
    DVTokenOwnershipList private _egregore_ownership_inventory;

    // Listing Devotees that belong to this Egregore
    DVTokenOwnershipList private _egregore_devotee_list;

    // Egregore listing
    DVTokenList private _wooden_egregores_list;
    DVTokenList private _accredited_egregores_list;

    /**
     * Worthy egregores that deserve to be processed this period
     */
    DVTokenList private _worthy_egregore_queue;    

    /**
     * Guilty egregores that pontentially could be punished during this period
     */
    DVTokenList private _guilty_egregore_queue;
    
    ///


    ///  ********** Devotee attributes **************** ///
    ///

    /// To which Egregore this devotee belongs to?
    mapping(uint256 => uint256) private _devotee_egregore_membership;

    /// Devotee ownership
    mapping(uint256 => address) private _devotee_owners;

    /// Devotee receiver wallets
    mapping(uint256 => address) private _devotee_receivers;

    /// Master bishop of this deacon devotee
    mapping(uint256 => uint256) private _devotee_master_bishop;

    /// Devotee referrer
    mapping(uint256 => uint256) private _devotee_referrer;

    /**
     * Percentaje of tribute that the Deacon Devotee has to pay for its related Bishop master, from the 
     * commissions after taxes. This is stablished by the master bishop.
     * If this devotee is bishop (having 0 in its master_bishop field),
     * then this field tells the commission fee that its subordinates have to pay.
     */
    mapping(uint256 => uint256) private _devotee_bishop_downline_commission_rate;

    /// Recruitment count performed by this devotee. It starts with 1 (devotee self counted)
    mapping(uint256 => uint) private _devotee_client_count;

    /// Accummulated commissions after taxes-
    mapping(uint256 => uint256) private _devotee_accummulated_commissions;


    // Devotee ownership inventory listing, assigned to owners addresses
    DVTokenOwnershipList private _devotee_ownership_inventory;


    // Devotee listing on egregore
    DVTokenOwnershipList private _devotee_egregore_listing;

    constructor() {
        _init_global_params();
    }

    
    function _init_global_params() private
    {
        
        _global_balance = 0;
        _global_admin_treasure = 0;
        _global_tax_rate = 500;// 5%
        _minimum_tax_per_period = 20000000;
        _punishment_periods_before_payout = 2;
        _seed_token_mint_price = 200000000;
        _seed_token_max_supply = 1000;
        _seed_token_minted_amount = 0;
        _egregore_id_gen = DV_DEFAULT_TOKEN_ID;
        _devotee_id_gen = DV_DEFAULT_TOKEN_ID;
    }

    
    /// Seed token operations
    ///
    function seed_balance(address owner_address) public view returns(uint256)
    {
        return _seed_token_balances[owner_address];
    }


    function transfer_seeds(address target_address, uint256 amount) public
    {
        address source = _msgSender();
        require(source != 0 && target_address != source && target_address != 0 && amount > 0, "Invalid parameters");

        uint256 _src_balance = _seed_token_balances[source];

        require(_src_balance >= amount, "Not enough balance");

        _seed_token_balances[source] = _src_balance - amount;

        _seed_token_balances[target_address] += amount;
    }


    function burn_seeds(uint256 amount) public
    {
        address source = _msgSender();
        require(source != 0 && amount > 0, "Invalid parameters");

        uint256 _src_balance = _seed_token_balances[source];
        require(_src_balance >= amount, "Not enough balance");

        _seed_token_balances[source] = _src_balance - amount;
    }


    function mint_seeds(uint256 amount) public payable
    {
        address source = _msgSender();

        require(source != 0 && amount > 0 , "Invalid parameters");

        uint256 final_balance = amount + _seed_token_minted_amount;

        require(final_balance <= _seed_token_max_supply, "Reached limit of minting amount");
        
        uint256 required_price = amount*_seed_token_mint_price;

        require(msg.value >= required_price, "Not enough funds");

        
        _seed_token_balances[source] += amount;
        _seed_token_minted_amount = final_balance;

        // add balance to global treasure
        _global_balance += required_price;
        /// Accummulated treasure from taxes. Will be used for promotion lottery
        _global_admin_treasure += required_price;

        if(msg.value  > required_price)
        {
            // transfer change
            _msgSender().transfer(msg.value  - required_price);
        }
    }

    ///

    function egregore_inventory(address owner_address) public view returns(DVTokenListInfo memory)
    {
        require(owner_address != address(0), "ERC1155: balance query for the zero address");
        DVTokenListInfo storage info = _egregore_ownership_inventory.owner_list_registry[DV_ADDRtoU256(owner_address)];
        return DVTokenListInfo({head:info.head, count:info.count});
    }

    function egregore_inventory_count(address owner_address) public view returns(uint)
    {
        require(owner_address != address(0), "ERC1155: balance query for the zero address");
        DVTokenListInfo storage info = _egregore_ownership_inventory.owner_list_registry[DV_ADDRtoU256(owner_address)];
        return info.count;
    }


    function devotee_inventory(address owner_address) public view returns(DVTokenListInfo memory)
    {
        require(owner_address != address(0), "ERC1155: balance query for the zero address");
        DVTokenListInfo storage info = _devotee_ownership_inventory.owner_list_registry[DV_ADDRtoU256(owner_address)];
        return DVTokenListInfo({head:info.head, count:info.count});
    }

    function devotee_inventory_count(address owner_address) public view returns(uint)
    {
        require(owner_address != address(0), "balance query for the zero address");
        DVTokenListInfo storage info = _devotee_ownership_inventory.owner_list_registry[DV_ADDRtoU256(owner_address)];
        return info.count;
    }

    /// Information about entities
    function fetch_egregore_info(uint256 egregore_ID) public view returns(EgregoreInfo memory)
    {
        EgregoreInfo memory ret_egregore;
        ret_egregore.egregoreID = egregore_ID;
        ret_egregore.owner_address = _egregore_owners[egregore_ID];
        EgregoreMeta storage metainfo = _egregore_meta[egregore_ID];

        ret_egregore.name = metainfo.name;
        ret_egregore.projectURL = metainfo.projectURL;
        ret_egregore.description = metainfo.description;

        EgregoreDevoteeMinting storage minting_info = _egregore_dev_minting[egregore_ID];

        ret_egregore.founder_token_reserve = minting_info.founder_token_reserve;
        ret_egregore.initial_mint_count = minting_info.initial_mint_count;

        EgregorePricing storage pricing = _egregore_pricing[egregore_ID];
        ret_egregore.floor_price = minting_info.floor_price;
        ret_egregore.minimum_commission = minting_info.minimum_commission;
        ret_egregore.commission_rate = minting_info.commission_rate;
        ret_egregore.insurance_rate = minting_info.insurance_rate;
        ret_egregore.insurance_risk_threshold = minting_info.insurance_risk_threshold;
        ret_egregore.graduation_threshold = minting_info.graduation_threshold;

        EgregoreBudget storage budget = _egregore_budget[egregore_ID];
        ret_egregore.egregore_treasure_vault = budget.egregore_treasure_vault;
        ret_egregore.project_payout_amount = budget.project_payout_amount;
        ret_egregore.insurance_vault = budget.insurance_vault;
        ret_egregore.accumulated_commissions = budget.accumulated_commissions;
        ret_egregore.tax_reserve = budget.tax_reserve;
        ret_egregore.is_worthy = budget.is_worthy;

        EgregorePrestige storage prestigeinfo = _egregore_prestige[egregore_ID];
        ret_egregore.promotion_status = prestigeinfo.promotion_status;
        ret_egregore.degree = prestigeinfo.degree;
        ret_egregore.grace_grapes = prestigeinfo.grace_grapes;
        ret_egregore.punsishment_periods = prestigeinfo.punsishment_periods;

        // calculate prestige score
        ret_egregore.prestige_score = EgregoreCalc.prestige_score(prestigeinfo);

        DVTokenListInfo storage devotee_collection = _egregore_devotee_list[egregore_ID];

        ret_egregore.devotee_count = devotee_collection.count;
        ret_egregore.devotee_list_head = devotee_collection.head;

        return ret_egregore;
    }

    function egregore_prestige_score(uint256 egregore_ID) public view returns(uint256)
    {
        EgregorePrestige storage prestigeinfo = _egregore_prestige[egregore_ID];
        return EgregoreCalc.prestige_score(prestigeinfo);
    }

    function devotee_social_capital_score(uint256 devotee_ID) public view returns(uint256)
    {
        // calculate social capital
        uint256 egregore_ID = _devotee_egregore_membership[devotee_ID];
        EgregorePrestige storage prestigeinfo = _egregore_prestige[egregore_ID];
        uint256 prestige_score = EgregoreCalc.prestige_score(prestigeinfo);
        return prestige_score * _devotee_client_count[devotee_ID];
    }

    function fetch_devotee_info(uint256 devotee_ID) public view returns(DevoteeInfo memory)
    {
        DevoteeInfo memory ret_devotee;
        ret_devotee.devoteeID = devotee_ID;
        ret_devotee.egregoreID = _devotee_egregore_membership[devotee_ID];
        ret_devotee.owner_address = DV_U256toADDR(_devotee_owners[devotee_ID]);
        ret_devotee.receiver_wallet = DV_U256toADDR(_devotee_receivers[devotee_ID]);
        ret_devotee.master_bishop = _devotee_master_bishop[devotee_ID];
        ret_devotee.referrer = _devotee_referrer[devotee_ID];

        ret_devotee.bishop_downline_commission_rate = _devotee_bishop_downline_commission_rate[devotee_ID];        
        ret_devotee.accummulated_commissions = _devotee_accummulated_commissions[devotee_ID];
        ret_devotee.client_count = _devotee_client_count[devotee_ID];

        EgregorePricing storage pricing = _egregore_pricing[ret_devotee.egregoreID];
        ret_devotee.graduation_threshold = pricing.graduation_threshold;

        uint256 prestige_score = egregore_prestige_score(ret_devotee.egregoreID);
        ret_devotee.social_capital_score = ret_devotee.client_count*prestige_score;
        return ret_devotee;
    }
    

    function _asSingletonArray(uint256 element) private pure returns (uint256[] memory) {
        uint256[] memory array = new uint256[](1);
        array[0] = element;

        return array;
    }
}

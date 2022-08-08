//SPDX-License-Identifier:MIT
pragma solidity >=0.8.4;

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

import "./DVList.sol";


uint256 constant DV_PERCENTAJE_FACTOR = 10000;
uint256 constant DV_MAX_COMMISSION_PERCENTAJE = 9000;//90%
uint256 constant DV_MAX_INSURANCE_PERCENTAJE = 5000;//50%
uint256 constant DV_MAX_INSURANCE_RISK_THRESHOLD = 5000;//50%
uint256 constant DV_MIN_INSURANCE_RISK_THRESHOLD = 100;//1%


uint256 constant DV_DEFAULT_TOKEN_ID = 1; // A reference value that is not used and could indicates a null.

// Prestige Grace Periods parameters
//
uint32 constant DV_ACCREDITED_AGE_INIT = 3;
uint32 constant DV_PIONEER_SPONSOR_PLANET_CURVE = 9;
uint32 constant DV_AGE_FOR_SPONSORSHIP = 9;
//


// Star promotion status
//
int16 constant DV_STATUS_UNACCREDITED = 0;
int16 constant DV_STATUS_GUILTY = -1;
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






struct StarMeta
{
    bytes32 name;
    /// URL of the official web site for the project
    string projectURL;
    string description;    
}

// Prestige promotion status
//
struct StarPrestige
{
    /**
     * Indicates how this Star would be promoted. Also indicates if it is
     * unaccredited or if it has its reputation damaged, with the following values:
     * 
     * - DV_STATUS_UNACCREDITED
     * - DV_STATUS_GUILTY
     * - DV_STATUS_ACCREDITED
     * - DV_STATUS_PARDONED
     * - DV_STATUS_SPONSORSHIP_BONUS
     * - DV_STATUS_HONORABLE_BONUS
     * - DV_STATUS_HONORABLE_SPONSOR_BONUS
     * - DV_STATUS_SPONSORSHIP_EXTRA_BONUS
     */
    int16 promotion_status;

    
    /// Prestige years
    uint32 grace_periods;

    /**
     * Punishment periods after declared guilty. Until a certain number of periods passed,
     * this Star gets downgrade by losing 1 year.
     */
    uint32 punsishment_periods;
}

/**
 * Price parameters for islands and commissions distribution
 */
struct StarPricing
{
    /// Island floor base price. It could vary depending of the planet bonding curve
    uint256 island_floor_price;

    /// Island percentaje factor for incrementing the base price taking the number of islands
    uint256 island_curve_price_rate;
    
    /// Minimum flat commission fee added to the price, before taxes.
    uint256 minimum_commission; 
    
    /// total commision before taxes, calculated on selling price.
    /// If 0, commission will be the diference between selling price and manor floor price
    uint256 commission_rate;

    /// Insurance tax percentaje, calculated over raw commission before taxes.
    uint256 insurance_rate;

    /**
     * Percentaje of the insurance pool that can be compromised. 
     * So when the defaulted obligations surpass this threshold,
     * it triggers a global downpayment to the insurance vault
     * where all members from the entire Star organization will be charged
     * during this period by losing their commissions.
     */
    uint256 insurance_risk_threshold;
    
}

/// Minting of Initial Planet Offering
struct StarPlanetMinting
{
    uint founder_planet__reserve;
    uint initial_planet__mint_count;
    uint256 planet_minting_price;
    bool planet_free_minting;
    bool island_free_minting;
}

struct StarBudget
{
    /**
     * Current Star Treasure Balance, which hasn't been liquidate yet.
     * 
     */
    uint256 star_treasure_vault;
    
    /**
     * Accumulated project payout to project maintainers. which has been substracted from  star_treasure_vault
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
     * If this Star remains unaccredited, the accummulated commissions
     * will be collected only for taxes.
     */
    uint256 tax_reserve;

    
    /// Is this Star declared worthy for this period
    bool is_worthy;
}

/// Declared macros
///

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


///



library StarCalc
{
    uint256 constant DV_PRESTIGE_ISLAND_DIVISOR = 1000;

    uint256 constant DV_PRESTIGE_ISLAND_DIVISOR_P3 = DV_PRESTIGE_ISLAND_DIVISOR * DV_PRESTIGE_ISLAND_DIVISOR * DV_PRESTIGE_ISLAND_DIVISOR;


    /**
     * Bonding curve for calculating the price of an Island depending of the emission rate.
     */
    function curve_floor_price(StarPricing storage starinfo, uint32 star_prestige, uint32 island_count) internal view returns(uint256)
    {
        uint256 scaled_island = uint256(island_count) * DV_PRESTIGE_ISLAND_DIVISOR;
        uint256 scaled_curve_factor = scaled_island / uint256(star_prestige);
        uint256 curve_rate_pow3 = starinfo.island_curve_price_rate * scaled_curve_factor * scaled_curve_factor * scaled_curve_factor;

        uint256 src_floor_price = starinfo.island_floor_price;
        /// in percentaje, needs to be divided by DV_PERCENTAJE_FACTOR
        uint256 price_factor_scaled = src_floor_price * curve_rate_pow3;

        uint256 price_increment = price_factor_scaled / DV_PRESTIGE_ISLAND_DIVISOR_P3;

        uint256 new_price_scaled = (src_floor_price * DV_PERCENTAJE_FACTOR) + price_increment;

        // fix percentaje
        return new_price_scaled / DV_PERCENTAJE_FACTOR;
    }

    function minimum_price(StarPricing storage starinfo, uint32 star_prestige, uint32 island_count) internal view returns(uint256)
    {
        uint256 bonded_curve_price = curve_floor_price(starinfo, star_prestige, island_count);
        return bonded_curve_price + starinfo.minimum_commission;
    }

    function percentaje(uint256 _selling_price, uint256 _percentaje) internal pure returns(uint256)
    {
        return  (_selling_price * _percentaje) /  DV_PERCENTAJE_FACTOR;
    }

    /**
    Calculate the commission over price before taxes.
    - floorprice must be calculated with the formula curve_floor_price(stinfo, star_prestige, island_count)
    - This assummes that selling_price is greater of equal than minimum price
     */
    function raw_commision(StarPricing storage stinfo, uint256 floorprice, uint256 selling_price) internal view returns(uint256)
    {
        uint256 mincommission = stinfo.minimum_commission;        
        uint256 minprice = floorprice + mincommission;
        if(selling_price <= minprice)
        {
            return mincommission;
        }
        else if(stinfo.commission_rate > 0)
        {
            // calculate percentaje for commission derived from the selling price
            uint256 factor_commission = (selling_price * stinfo.commission_rate) /  DV_PERCENTAJE_FACTOR;
            // how much funds left for the Star project?
            uint256 collected_funds_base = selling_price - factor_commission;
            
            if(collected_funds_base < floorprice || factor_commission < mincommission)
            {
                return mincommission;
            }

            return factor_commission;            
        }

        return selling_price - floorprice;
    }
}

/**
 * Star Descriptive information
 * @remarks Within DAOVOTION contract, Star fields are represented different, as sparsed mapping hash tables.
 */
struct StarInfo
{
    /// Id of this Star Token
    uint256 starID;

    /// Owner Wallet that controls this Star
    /**
     * @remarks If 0, then this Star is not longer controlled by its owner, 
       but instead it has an stablished governance where its manor members have voting power
       on deciding how to distribute funds and change parameters-
       By default, this receiver_wallet should be assigned to the Owner.
     */
    address owner_address;

    
    /**
     * Sponsor Star.
     */
    uint256 sponsor_starID;

    /// Name of the project
    bytes32 name;
    /// URL of the official web site for the project
    string projectURL;
    string description;

    /// Foundational parameters for emitting Planet Tokens
    ///
    uint founder_planet__reserve;
    uint initial_planet__mint_count;
    uint256 planet_minting_price;
    bool planet_free_minting;
    bool island_free_minting;
    ///

    /// Island floor base price. It could vary depending of the planet bonding curve
    uint256 island_floor_price;

    /// Island percentaje factor for incrementing the base price taking the number of islands
    uint256 island_curve_price_rate;
    
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
     * where all members from the entire Star organization will be charged
     * during this period by losing their commissions.
     */
    uint256 insurance_risk_threshold;
    
    /**
     * Threshold of Manor acquisitions that a landlord has to achive to becomming an Island Regent.
     * This is stablished by the Star.
     */
    uint graduation_threshold;

    /**
     * Current Star Treasure Balance, which hasn't been liquidate yet.
     * 
     */
    uint256 star_treasure_vault;
    
    /**
     * Accumulated project payout to project maintainers. which has been substracted from  star_treasure_vault
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
     * If this Star remains unaccredited, the accummulated commissions
     * will be collected only for taxes.
     */
    uint256 tax_reserve;

    
    /// Is this Star declared worthy for this period
    bool is_worthy;


    

    /**
     * Indicates how this Star would be promoted. Also indicates if it is
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

    /// Prestige grace periods
    uint32 grace_periods;

    /**
     * Punishment periods after declared guilty. Until a certain number of periods passed,
     * this Star gets downgrade by losing 1 grace grape.
     */
    uint32 punsishment_periods;
}

/**
    Manor descriptive information
    @remarks Within DAOVOTION contract, manors fields are represented different, as sparsed mapping hash tables.
 */
struct ManorInfo
{
    /// Id of this Manor Token
    uint256 manorID;

    /// Star which this Manor belongs to,
    uint256 starID;
    
    /**
     * Owner Wallet that controls this Manor.   
     */
    address owner_address;

    /// Receiver account that will collect the commmission payments.
    address receiver_wallet;

    /// Reference to a Island Kingship. 0 defines this manor as Island Kingship.
    uint256 island_kingship;
        
    /**
     * Seller that offered this new manor. Could be the same Island King, or a Landlord. 0 if it is foundational member.
     */
    uint256 referrer; 

    /**
     * Percentaje of the commision that a landlord would obtain for selling a new manor from the same Island.
     * The rest of the commission will be paid to the Island Kingship, as the manor_floor_base will be paid to the Star project.
     */
    uint256 ambassador_commission_rate;


    /**
     * Accummulated commissions obtained by the land sales during the Grace period. 
     */
    uint256 accummulated_commissions;


    /**
     * Threshold amount of referred Manors that a landlord has to sell for becomming a Island King.
     * This is stablished by the Star parameters.
     */
    uint graduation_threshold;

    /**
     * Number of derived manor sales that a landlord has achieved by using the current manor title.
     * If derived_manor_count reaches the graduation_threshold, this Manor becomes an Island Kingship.
     * @remarks Each time a landlord realizes a sale, the derived_manor_count is also incremented on the 
     * related Island Kingship incresing its social capital score.
     */
    uint derived_manor_count;


    /// Calculated prestige score, including the Star prestige score factor
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
     * Minimum commissions ammount that an Star has to 
     * collect in taxes (~ 5% global tax) in order to be considerd "Worthy",
     * So it could being processed and get promoted during this periods.
     */
    uint256 minimum_tax_per_period;

    /**
     * Number of periods that has to be elapsed before
     * the guilty Star has to be punished by losing another grace grape.
     */
    uint32 punishment_periods_before_payout;
    ///

    /// Price for minting nucleus tokens
    uint256 nucleus_token_mint_price;

    /// maximum nucleus token supply
    uint256 nucleus_token_max_supply;

    /// Current nucleus token minted
    uint256 nucleus_token_minted_amount;
}

/**
 * DAOVOTION handles 6 kinds of tokens:
 * - 1 : NUCLEUS token. Used for creating Stars.
 * - 2 : STAR token. Identifies a DAO corporation known as Star.
 * - 3 : MANOR token. Identifies a DAO member of an Star.
 * - 4 : PUZZLE token. Identifies a puzzle piece for the governance game.
 * - 5 : BULL token. Identifies an advanced puzzle piece for the governance game.
 * - 6 : ARCHANGEL token. Identifies a governance token that are used for promoting Stars.
 * 
 *  Devotee tokens could being related each other and are intrinsically linked to an Star. 
 */
contract DAOVOTION is Ownable, ReentrancyGuard, ERC165 {
    using Address for address;

    // for lists
    using DVTokenListUtil for DVTokenList;

    using DVTokenOwnershipListUtil for DVTokenOwnershipList;

    using DVStackArrayUtil for DVStackArray;

    event NewStarCreated(address indexed owner, uint256 star_id);

    event NewDevoteeMinted(address indexed owner, uint256 star_id, uint256 manor_id, uint256 referrer_id);

    event StarPromoted(uint256 star_id, uint16 degree);
    
    ///  ********** Global Balance **************** ///
    ///
    
    
    /**
     * Global balance.
     * This is the amount of capital that this contract has been received.
     * From this global balance, this contract will draw funds to each Star budget and to each manor commission payout.
     */
    uint256 private _global_balance;

    /// Accummulated treasure from taxes. Will be used for promotion lottery
    uint256 private _global_admin_treasure;

    
    ///  ********** Global parameters **************** ///
    ///
    /// Global tax percentaje from commissions (5%)
    uint256 private _global_tax_rate;


    /**
     * Minimum commissions ammount that an Star has to 
     * collect in taxes (~ 5% global tax) in order to be considerd "Worthy",
     * So it could being processed and get promoted during this periods.
     */
    uint256 private _minimum_tax_per_period;

    /**
     * Number of periods that has to be elapsed before
     * the guilty Star has to be punished by losing another grace grape.
     */
    uint32 private _punishment_periods_before_payout;
    ///

    ///  ********** Global Promotion parameters **************** ///
    ///

    /**
     * Minimum amount of tax revenue that an Star has to collect in order 
     * to being nominated for the Promotion Lottery
     */
    uint256  _minimum_promotion_tax_revenue;

    /**
     * Minimum number of manors that an Star has to subscribe in order 
     * to being nominated for the Promotion Lottery
     */
    uint32  _minimum_promotion_manor_count;
    ///

    ///  ********** Minting variables **************** ///
    ///
    /// Price for minting nucleus tokens
    uint256 private _nucleus_token_mint_price;

    /// maximum nucleus token supply
    uint256 private _nucleus_token_max_supply;

    /// Current nucleus token minted
    uint256 private _nucleus_token_minted_amount;

    /// Generates stars consecutives hashes
    uint256 private _star_id_gen;
    /// Generates manors consecutives hashes
    uint256 private _manor_id_gen;    
    ///

    

    ///  ********** Fungible tokens for minting Stars **************** ///
    ///
    /// Balances for fungible nucleus tokens
    mapping(address => uint256) private _nucleus_token_balances;
    ///

    ///  ********** Star attributes **************** ///
    ///
    // Stars Info
    mapping(uint256 => StarMeta) private _star_meta;

    
    // Stars pricing
    mapping(uint256 => StarPricing) private _star_pricing;

    // Stars prestige
    mapping(uint256 => StarPrestige) private _star_prestige;

    // Stars budget
    mapping(uint256 => StarBudget) private _star_budget;

    // Stars minting for Devotees
    mapping(uint256 => StarDevoteeMinting) private _star_dev_minting;
    
    // Star receiver addresses
    mapping(uint256 => address) private _star_receivers;

    // Star owner addresses
    mapping(uint256 => address) private _star_owners;


    // Star sponsors - reference mapping to sponsor Star
    mapping(uint256 => uint256) private _star_sponsors;

    // Stars Ownership to addresses
    DVTokenOwnershipList private _star_ownership_inventory;

    // Listing Devotees that belong to this Star
    DVTokenOwnershipList private _star_manor_list;

    // Star listing
    DVTokenList private _wooden_stars_list;
    DVTokenList private _accredited_stars_list;

    /**
     * Worthy stars that deserve to be processed in the current period
     */
    DVStackArray private _worthy_stars_queue;

    /**
     * Guilty stars that pontentially could be punished during the current period.
     * But also these could be pardoned during the promotion Lottery.
     */
    DVStackArray private _guilty_stars_pool;


    /**
     * Unacredited Stars nominated to be elected during the Promotion Lottery
     */
    DVStackArray private _promoting_stars_pool;
    
    ///


    ///  ********** Devotee attributes **************** ///
    ///

    /// To which Star this manor belongs to?
    mapping(uint256 => uint256) private _manor_star_membership;

    /// Devotee ownership
    mapping(uint256 => address) private _manor_owners;

    /// Devotee receiver wallets
    mapping(uint256 => address) private _manor_receivers;

    /// Master bishop of this deacon manor
    mapping(uint256 => uint256) private _manor_island_kingship;

    /// Devotee referrer, can be 0
    mapping(uint256 => uint256) private _manor_referrer;

    /**
     * Percentaje of tribute that the Deacon Devotee has to pay for its related Bishop master, from the 
     * commissions after taxes. This is stablished by the master bishop.
     * If this manor is bishop (having 0 in its island_kingship field),
     * then this field tells the commission fee that its subordinates have to pay.
     */
    mapping(uint256 => uint256) private _manor_bishop_downline_commission_rate;

    /// Recruitment count performed by this manor. It starts with 1 (manor self counted)
    mapping(uint256 => uint) private _manor_client_count;

    /// Accummulated commissions after taxes-
    mapping(uint256 => uint256) private _manor_accummulated_commissions;


    // Devotee ownership inventory listing, assigned to owners addresses
    DVTokenOwnershipList private _manor_ownership_inventory;


    // Devotee listing on star
    DVTokenOwnershipList private _manor_star_listing;

    /// Whitelisting
    /**
     * Star Minting whitelisting.
     * Authorization for minting a ceratin number of manor tokens to a determined address
     */
    mapping(bytes32 => uint) private _star_minting_whitelist;


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

        _minimum_promotion_tax_revenue = 40000000;
        _minimum_promotion_manor_count = 10;

        _nucleus_token_mint_price = 200000000;
        _nucleus_token_max_supply = 1000;
        _nucleus_token_minted_amount = 0;
        _star_id_gen = DV_DEFAULT_TOKEN_ID;
        _manor_id_gen = DV_DEFAULT_TOKEN_ID;
    }

    
    /// Seed token operations
    ///
    function nucleus_balance(address owner_address) external view returns(uint256)
    {
        return _nucleus_token_balances[owner_address];
    }


    function transfer_nucleus(address target_address, uint256 amount) external nonReentrant
    {
        address source = _msgSender();
        require(source != address(0) &&
                target_address != source &&
                target_address != address(0) &&
                amount > 0, "Invalid parameters");

        uint256 _src_balance = _nucleus_token_balances[source];

        require(_src_balance >= amount, "Not enough balance");

        _nucleus_token_balances[source] = _src_balance - amount;

        _nucleus_token_balances[target_address] += amount;
    }


    function burn_nucleus(uint256 amount) external nonReentrant
    {
        address source = _msgSender();
        require(source != address(0) && amount > 0, "Invalid parameters");

        uint256 _src_balance = _nucleus_token_balances[source];
        require(_src_balance >= amount, "Not enough balance");

        _nucleus_token_balances[source] = _src_balance - amount;
    }


    function mint_nucleus(uint256 amount) external payable nonReentrant
    {
        address payable source = payable(msg.sender);

        require(source != address(0) && amount > 0 , "Invalid parameters");

        uint256 final_balance = amount + _nucleus_token_minted_amount;

        require(final_balance <= _nucleus_token_max_supply, "Reached limit of minting amount");
        
        uint256 required_price = amount*_nucleus_token_mint_price;

        require(msg.value >= required_price, "Not enough funds");

        
        _nucleus_token_balances[source] += amount;
        _nucleus_token_minted_amount = final_balance;

        // add balance to global treasure
        _global_balance += required_price;
        /// Accummulated treasure from taxes. Will be used for promotion lottery
        _global_admin_treasure += required_price;

        if(msg.value  > required_price)
        {
            // transfer change
            source.transfer(msg.value  - required_price);
        }
    }

    ///

    function star_inventory(address owner_address) external view returns(DVTokenListInfo memory)
    {
        require(owner_address != address(0), "ERC1155: balance query for the zero address");
        DVTokenListInfo storage info = _star_ownership_inventory.sinfo(DVF_ADDRtoU256(owner_address));
        return DVTokenListInfo({head:info.head, count:info.count});
    }

    function star_inventory_count(address owner_address) external view returns(uint)
    {
        require(owner_address != address(0), "ERC1155: balance query for the zero address");
        DVTokenListInfo storage info = _star_ownership_inventory.sinfo(DVF_ADDRtoU256(owner_address));
        return info.count;
    }


    function manor_inventory(address owner_address) external view returns(DVTokenListInfo memory)
    {
        require(owner_address != address(0), "ERC1155: balance query for the zero address");
        DVTokenListInfo storage info = _manor_ownership_inventory.sinfo(DVF_ADDRtoU256(owner_address));
        return DVTokenListInfo({head:info.head, count:info.count});
    }

    function manor_inventory_count(address owner_address) external view returns(uint)
    {
        require(owner_address != address(0), "balance query for the zero address");
        DVTokenListInfo storage info = _manor_ownership_inventory.sinfo(DVF_ADDRtoU256(owner_address));
        return info.count;
    }

    /// Information about entities
    function fetch_star_info(uint256 star_ID) external view returns(StarInfo memory)
    {
        StarInfo memory ret_star;
        ret_star.starID = star_ID;
        ret_star.owner_address = _star_owners[star_ID];
        StarMeta storage metainfo = _star_meta[star_ID];

        ret_star.name = metainfo.name;
        ret_star.projectURL = metainfo.projectURL;
        ret_star.description = metainfo.description;

        StarDevoteeMinting storage minting_info = _star_dev_minting[star_ID];

        ret_star.founder_token_reserve = minting_info.founder_reserve;
        ret_star.initial_mint_count = minting_info.initial_mint_count;
        ret_star.free_minting = minting_info.free_minting;

        StarPricing storage pricing = _star_pricing[star_ID];
        ret_star.manor_floor_price = pricing.manor_floor_price;
        ret_star.minimum_commission = pricing.minimum_commission;
        ret_star.commission_rate = pricing.commission_rate;
        ret_star.insurance_rate = pricing.insurance_rate;
        ret_star.insurance_risk_threshold = pricing.insurance_risk_threshold;
        ret_star.graduation_threshold = pricing.graduation_threshold;

        StarBudget storage budget = _star_budget[star_ID];
        ret_star.star_treasure_vault = budget.star_treasure_vault;
        ret_star.project_payout_amount = budget.project_payout_amount;
        ret_star.insurance_vault = budget.insurance_vault;
        ret_star.accumulated_commissions = budget.accumulated_commissions;
        ret_star.tax_reserve = budget.tax_reserve;
        ret_star.is_worthy = budget.is_worthy;

        StarPrestige storage prestigeinfo = _star_prestige[star_ID];
        ret_star.promotion_status = prestigeinfo.promotion_status;
        ret_star.degree = prestigeinfo.degree;
        ret_star.grace_moons = prestigeinfo.grace_moons;
        ret_star.punsishment_periods = prestigeinfo.punsishment_periods;

        // calculate prestige score
        ret_star.prestige_score = StarCalc.prestige_score(prestigeinfo);

        DVTokenListInfo storage manor_collection = _star_manor_list.sinfo(star_ID);

        ret_star.manor_count = manor_collection.count;
        ret_star.manor_list_head = manor_collection.head;

        return ret_star;
    }

    function star_prestige_score(uint256 star_ID) external view returns(uint256)
    {
        StarPrestige storage prestigeinfo = _star_prestige[star_ID];
        return StarCalc.prestige_score(prestigeinfo);
    }

    function star_prestige_score_in(uint256 star_ID) internal view returns(uint256)
    {
        StarPrestige storage prestigeinfo = _star_prestige[star_ID];
        return StarCalc.prestige_score(prestigeinfo);
    }


    function manor_social_capital_score(uint256 manor_ID) external view returns(uint256)
    {
        // calculate social capital
        uint256 star_ID = _manor_star_membership[manor_ID];
        StarPrestige storage prestigeinfo = _star_prestige[star_ID];
        uint256 prestige_score = StarCalc.prestige_score(prestigeinfo);
        return prestige_score * _manor_client_count[manor_ID];
    }

    function fetch_manor_info(uint256 manor_ID) external view returns(DevoteeInfo memory)
    {
        DevoteeInfo memory ret_manor;
        ret_manor.manorID = manor_ID;
        ret_manor.starID = _manor_star_membership[manor_ID];
        ret_manor.owner_address = _manor_owners[manor_ID];
        ret_manor.receiver_wallet = _manor_receivers[manor_ID];
        ret_manor.island_kingship = _manor_island_kingship[manor_ID];
        ret_manor.referrer = _manor_referrer[manor_ID];

        ret_manor.bishop_downline_commission_rate = _manor_bishop_downline_commission_rate[manor_ID];        
        ret_manor.accummulated_commissions = _manor_accummulated_commissions[manor_ID];
        ret_manor.client_count = _manor_client_count[manor_ID];

        StarPricing storage pricing = _star_pricing[ret_manor.starID];
        ret_manor.graduation_threshold = pricing.graduation_threshold;

        uint256 prestige_score = star_prestige_score_in(ret_manor.starID);
        ret_manor.social_capital_score = ret_manor.client_count*prestige_score;
        return ret_manor;
    }
    

    /// Star creation
    ///

    /**
     *  Creates a new Star, by consuming an nucleus token.
     *  returns the ID of the new created Star, or returns 
     */
    function create_star(StarMeta calldata metainfo, 
                             StarPricing calldata pricing,
                             uint initial_mint_count,
                             uint founder_reserve,
                             bool free_minting) external nonReentrant returns(uint256)
    {
        address source = _msgSender();
        require(source != address(0), "Invalid ownership address");

        /// check balance, and consume token
        uint256 _src_balance = _nucleus_token_balances[source];
        require(_src_balance >= 1, "Not enough nucleus balance");

        // Generate Star ID
        _star_id_gen += 1;

        uint256 newStarID = _star_id_gen;

        // create star information

        _star_meta[newStarID] = StarMeta({name:metainfo.name, projectURL:metainfo.projectURL,  description:metainfo.description});


        // Assign pricing parameters
        StarPricing storage _pricing_info = _star_pricing[newStarID];
        _pricing_info.manor_floor_price = pricing.manor_floor_price;
        _pricing_info.minimum_commission = pricing.minimum_commission;
        uint256 _commissionrate = pricing.commission_rate;
        uint256 _insurance_rate = pricing.insurance_rate;
        uint256 _insurance_risk = pricing.insurance_risk_threshold;
        _pricing_info.commission_rate = _commissionrate > DV_MAX_COMMISSION_PERCENTAJE ?  DV_MAX_COMMISSION_PERCENTAJE: _commissionrate;
        _pricing_info.insurance_rate = _insurance_rate > DV_MAX_INSURANCE_PERCENTAJE ?  DV_MAX_INSURANCE_PERCENTAJE: _insurance_rate;
        _pricing_info.insurance_risk_threshold = _insurance_risk > DV_MAX_INSURANCE_RISK_THRESHOLD ?
                                                              DV_MAX_INSURANCE_RISK_THRESHOLD:
                                                              (_insurance_risk < DV_MIN_INSURANCE_RISK_THRESHOLD ?   DV_MIN_INSURANCE_RISK_THRESHOLD : _insurance_risk);


        _pricing_info.graduation_threshold = pricing.graduation_threshold;


        // Assign initial minting parameters
        _star_dev_minting[newStarID] = StarDevoteeMinting({founder_reserve:founder_reserve,
                                                                       initial_mint_count:initial_mint_count,
                                                                       free_minting:free_minting});

        // initialize budget
        _star_budget[newStarID] = StarBudget({
            star_treasure_vault:uint256(0),
            project_payout_amount:uint256(0),
            insurance_vault:uint256(0),
            accumulated_commissions:uint256(0),
            tax_reserve:uint256(0),
            is_worthy:false
        });

        // initialize prestige
        _star_prestige[newStarID] = StarPrestige({
            promotion_status:DV_STATUS_UNACCREDITED,
            degree:DV_MIST_DEGREE,
            grace_moons:uint32(0),
            punsishment_periods:(0)
        });

        
        // assign owner and receiver
        _star_owners[newStarID] = source;
        _star_receivers[newStarID] = source;

        // include in the owner inventory
        _star_ownership_inventory.insert(DVF_ADDRtoU256(source), newStarID);

        // insert in the wooden star list
        _wooden_stars_list.insert(newStarID);


        // consume nucleus 
        _nucleus_token_balances[source] = _src_balance - 1;

        // Star already created
        emit NewStarCreated(source, newStarID);

        return newStarID;
    }


    function allow_star_minting_whitelist_for(uint256  starID, address allowed_address, uint number_of_mints) external
    {
        address owner = _star_owners[starID];
        require(owner != address(0), "Invalid ownership address");

        require(owner == _star_owners[starID], "Star must be owned by calling address");

        uint minting_reserve = _star_dev_minting[starID].initial_mint_count;
        require(minting_reserve > 0, "Not enough reserved minting");

        uint allowed_mints =  number_of_mints > minting_reserve ? minting_reserve : number_of_mints;

        // generate hash
        bytes32 allow_hash = keccak256(abi.encodePacked(allowed_address, starID, owner));

        // store whitelist
        _star_minting_whitelist[allow_hash] = allowed_mints;
    }

    /**
     * Check if the target address is allowed to mint manor tokens in the foundational phase
     * post: this decrements the number of mints allowed.
     */
    function is_allowed_to_mint_star_manor(uint256 starID, address target_address) internal returns(bool)
    {
        address owneraddr = _star_owners[starID];
        bytes32 allow_hash = keccak256(abi.encodePacked(target_address, starID, owneraddr));
        uint allowed_mints = _star_minting_whitelist[allow_hash];
        if(allowed_mints == 0) return false;
        _star_minting_whitelist[allow_hash] = allowed_mints - 1;// discount 1 mint
        return true;
    }

    function create_manor_record(uint256 starID,
                            address owner_address,
                            uint256 bishop_ID,
                            uint256 referrer_ID,
                            uint256 downline_commission_rate) internal returns(uint256)
    {
        // create new manor
        _manor_id_gen++;
        uint256 newmanorID = _manor_id_gen;
        _manor_star_membership[newmanorID] = starID;
        _manor_owners[newmanorID] = owner_address;
        _manor_receivers[newmanorID] = owner_address;
        _manor_island_kingship[newmanorID] = bishop_ID; // as bishop
        _manor_referrer[newmanorID] = referrer_ID; // no referrer
        _manor_bishop_downline_commission_rate[newmanorID] = downline_commission_rate;
        _manor_client_count[newmanorID] = 1;
        _manor_accummulated_commissions[newmanorID] = uint256(0);


        // collect in the owner inventory
        _manor_ownership_inventory.insert(DVF_ADDRtoU256(owner_address), newmanorID);
        // include in the star listing
        _manor_star_listing.insert(starID, newmanorID);

        return newmanorID;
    }

    function mint_foundational_manor(uint256  starID, uint256 downline_commission_rate) external payable nonReentrant returns(uint256)
    {
        require(_star_prestige[starID].degree == DV_MIST_DEGREE, "Cannot mint foundational tokens on evolved Stars");
        
        StarDevoteeMinting storage mint_info = _star_dev_minting[starID];

        require(mint_info.initial_mint_count > 0, "Exceeded number of mints");

        require(msg.sender != address(0), "Invalid address");


        StarPricing storage pricing_info = _star_pricing[starID];

        uint256 minprice = StarCalc.minimum_price(pricing_info);

        require(msg.value >= minprice, "Not enough funds");

        if(mint_info.free_minting == false)
        {
            // check minting
            bool allow_mint = is_allowed_to_mint_star_manor(starID, msg.sender); // this discount minting count
            require(allow_mint == true, "Not allowed to Mint Devotee");
        }

        // discount minting count
        mint_info.initial_mint_count--;

        uint256 rawcommission = StarCalc.raw_commision(pricing_info, msg.value);

        // calculate insurance discount
        uint256 discounted_insurance = StarCalc.percentaje(rawcommission, pricing_info.insurance_rate);
        uint256 tax_contribution = rawcommission - discounted_insurance;
        uint256 base_value = msg.value - rawcommission;

        // account contribution and balance

        StarBudget storage e_budget = _star_budget[starID];

        e_budget.star_treasure_vault += base_value;
        e_budget.insurance_vault += discounted_insurance;
        e_budget.tax_reserve += tax_contribution;

        // Contribute to global balance
        _global_balance += msg.value;
        _global_admin_treasure += tax_contribution;

        // create new manor        
        uint256 newmanorID = create_manor_record(starID, msg.sender, uint256(0),uint256(0), downline_commission_rate);

        // check promotion from taxes        
        if(e_budget.tax_reserve >=  _minimum_promotion_tax_revenue)
        {
            // check if it has already enough manors
            if(_manor_ownership_inventory.count(starID) >= _minimum_promotion_manor_count)
            {
                // include in the promotion pool
                // (note that an Star can be inserted multiple times in the promotion pool if it collects more taxes)
                _promoting_stars_pool.insert(starID);
                // discount tax
                e_budget.tax_reserve -= _minimum_promotion_tax_revenue;
            }
        }

        emit NewDevoteeMinted(msg.sender, starID, newmanorID, uint256(0));

        return newmanorID;
    }


    function mint_reserved_manor(uint256  starID, uint256 downline_commission_rate) external nonReentrant returns(uint256)
    {
        require(_star_prestige[starID].degree != DV_NULL_DEGREE, "Cannot mint tokens on null Stars");
        
        StarDevoteeMinting storage mint_info = _star_dev_minting[starID];

        require(mint_info.founder_reserve > 0, "Exceeded number of mints");

        address owneraddr = _star_owners[starID];
        require(owneraddr != msg.sender, "Not authorized for accessing to reserved tokens");

        // discount minting count
        mint_info.founder_reserve--;

        // create new manor
        uint256 newmanorID = create_manor_record(starID, owneraddr, uint256(0),uint256(0),downline_commission_rate);
        
        emit NewDevoteeMinted(owneraddr, starID, newmanorID, uint256(0));

        return newmanorID;
    }

    function transfer_star(uint256 starID, address target_address) external
    {
        address source = _msgSender();
        require(source != address(0) &&
                target_address != source &&
                target_address != address(0), "Invalid parameters");

        require(source == _star_owners[starID], "Star doesn't belong to caller address");

        _star_ownership_inventory.remove(DVF_ADDRtoU256(source), starID);

        _star_ownership_inventory.insert(DVF_ADDRtoU256(target_address), starID);

        _star_owners[starID] = target_address;
    }

    function transfer_manor(uint256 manorID, address target_address) external
    {
        address source = _msgSender();
        require(source != address(0) &&
                target_address != source &&
                target_address != address(0), "Invalid parameters");

        require(source == _manor_owners[manorID], "Devotee doesn't belong to caller address");

        _manor_ownership_inventory.remove(DVF_ADDRtoU256(source), manorID);

        _manor_ownership_inventory.insert(DVF_ADDRtoU256(target_address), manorID);

        _manor_owners[manorID] = target_address;        
    }


    function manor_billing_hash(uint256 ref_manorID, uint256 token_price, address buyer_address) internal view returns(uint256)
    {

    }


    /**
     * Sell derived manor
     */
    function buy_manor(uint256 ref_manorID, uint256 token_price, bytes memory billing_signature) external payable nonReentrant returns(uint256)
    {

    }
    ///
    
}
/**
    TODO:
    1. Create a list with tail and allows to push to tail and remove to tail. Useful
       For processing queues.
    2. Implement Promotion lottery events.

    3. Implement Arbitration Trials.

    4. Implement governance voting on proposals to the Star.

    5. Implement Escrow budget management for Stars, with Devotee governance voting.
 */
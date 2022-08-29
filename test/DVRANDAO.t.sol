// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.8;

import "forge-std/Test.sol";
import "../src/DVRANDAO.sol";
import "openzeppelin-contracts/contracts/utils/Strings.sol";

contract DVRANDAOTest is Test {
    using stdStorage for StdStorage;

    DVRANDAO private randao;    
    mapping(uint32 => address) private _address_set;
    mapping(uint32 => uint256) private _private_keys_set;
	uint32 private _num_keys;
	uint256 private _task_ID;
	VRFCircleProblem _test_circle_problem;	

    function setUp() public {
		_num_keys = 0;
		_task_ID = uint256(1);
		// Deploy NFT contract
        randao = new DVRANDAO();
        console.log("Contract DVRANDAO Deployed At", address(randao));

		// create a custom Circle Problem contract for testing
		_test_circle_problem = new VRFCircleProblem(randao.get_random_seed());
		create_keys();
    }

	function _generate_key(uint256 pkey_hash) internal
	{
		string memory str_hash = Strings.toHexString(pkey_hash);
		console.log("- Private Key ", str_hash);
        _private_keys_set[_num_keys] = pkey_hash;
		address addrkey = vm.addr(pkey_hash);
		console.log("- Public Key ", addrkey);
        _address_set[_num_keys] = addrkey;
		_num_keys++;
	}

	function _generate_key_raw(uint256 private_key, address public_key) internal
	{		
        _private_keys_set[_num_keys] = private_key;
        _address_set[_num_keys] = public_key;
		_num_keys++;
	}

	function create_keys() internal
	{
		uint32 total_keys = 8;
		console.log("**Generating Keys", total_keys);
		// mnemonic need 12 word
		for(uint32 i = 0; i < total_keys; i++)
		{
			uint256 rnd_number = _test_circle_problem.next_rnd_number();
			_generate_key(rnd_number);
		}
	}

	function create_keys0() internal
	{
		console.log("Generating Keys Raw");
		
		_generate_key_raw(
			uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80),
			address(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266)
		);

		_generate_key_raw(
			uint256(0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d),
			address(0x70997970C51812dc3A010C7d01b50e0d17dc79C8)
		);

        _generate_key_raw(
			uint256(0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a),
			address(0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC)
		);
	}

	function create_islands() internal
	{
		console.log("\n*** Create Islands ***\n");
		uint256 islandID = 1;
		uint32 islands_x_addr = 5;
		for(uint32 i = 0; i < _num_keys; i++)
		{
			address owner_pk = _address_set[i];
			for(uint32 j = 0; j < islands_x_addr; j++)
			{
				// create islands
				console.log("\nAttemmpting to create Island ", islandID, ", For Address ", owner_pk);
				randao.register_island(islandID, owner_pk);
				islandID++;
			}			
		}
	}

	function create_tasks(uint32 num_tasks) internal
	{
		console.log("\n*** Create Tasks ***\n");
		uint256  max_bounty = address(this).balance / 10000000000;

		for(uint32 i = 0; i < num_tasks; i++)
		{
			uint256 rnd_number = _test_circle_problem.next_rnd_number();
			uint256 bounty = rnd_number % max_bounty;
			console.log("\nAttemmpting to create a task ", _task_ID, ", With Bounty = ", bounty);
			randao.create_new_task{value:bounty}(_task_ID);
			_task_ID++;
		}
	}

	function create_problem() internal
	{
		_test_circle_problem.restart_problem();

		console.log("\n***Creating a problem *** ");
		bool isfinished = false;
		uint32 iterations = 0;
		
		while(isfinished == false)
		{
			isfinished = _test_circle_problem.insert_new_circle();
			iterations++;
		}

		console.log("\n=> Problem created in ", iterations, " iterations.");
	}

	function testRecordSignature() public {
        
        // set balance        
        vm.deal(_address_set[0], 1000 ether);
        vm.deal(_address_set[1], 1000 ether);
        vm.deal(_address_set[2], 1000 ether);

        // transfer funds        
        vm.deal(address(this), 1000 ether);

        // Create Islands
        create_islands();
        
		// create tasks
		create_tasks(10);

        // generate private key and insert record
        uint256 test_island = uint256(1);
        int64 cx = 236223201280;
        int64 cy = 24696061952;
        int64 radius = 5570035712;

        bytes32 circle_island1_hash = randao.digital_record_signature_helper(test_island, cx, cy, radius);

        // obtain signature for new record
        bytes32 eth_digest1 = ECDSA.toEthSignedMessageHash(circle_island1_hash);// adapt to Ethereum signature format

        (uint8 parity_v, bytes32 sign_r, bytes32 sign_s) = vm.sign(_private_keys_set[0], eth_digest1);

        // insert new record
        uint256 newrecord1 = randao.insert_record_own{value:VRF_RECORD_STORAGE_FEE}(test_island, _address_set[0], sign_r, sign_s, parity_v);

        // test record signature
        bool isvalid = randao.is_valid_record_signature(newrecord1, _address_set[0], cx, cy, radius);

        assertEq(isvalid, true);
    }

	function testCircleCreation() public {
		create_problem();

		// set balance        
        vm.deal(_address_set[0], 1000 ether);
        vm.deal(_address_set[1], 1000 ether);
        vm.deal(_address_set[2], 1000 ether);

        // transfer funds        
        vm.deal(address(this), 1000 ether);

        // Create Islands
        create_islands();
        
		// create tasks
		create_tasks(10);
	}

    
}

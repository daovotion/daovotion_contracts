//SPDX-License-Identifier:MIT
pragma solidity >=0.8.8;

import "../util/FixMath.sol";
import "../util/PCGRandomLib.sol";
import "../util/DVControlable.sol";
import "../util/DVStackArray.sol";
import "openzeppelin-contracts/contracts/utils/introspection/ERC165.sol";


error Err_InvalidAddressParams();

// VRF Problem
uint32 constant VRF_CIRCLES_COUNT = 16;
int64 constant VRF_PROBLEM_AREA = 0x20000000000; //512.00 fix32
int64 constant VRF_PROBLEM_MAXRADIUS = VRF_PROBLEM_AREA >> 2;

struct VRFCircle {
    int64 x;
    int64 y;
    int64 radius;
}


struct VRFCircleProblemSnapshot 
{
    int64 problem_area_size;	
	int64 max_circle_radius;
	int64 solution_min_radius;
    VRFCircle[] static_circles;
}


library VRFCircleProblemLib
{
	function create_circle_rnd(
        VRFCircle storage target_circle,
        uint256 seed,
        uint64 problem_area_size,
        uint64 max_circle_radius
    ) internal {
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
        target_circle.radius = int64(u_radius % max_circle_radius);
    }

    function create_circle_rnd_mem(
        uint256 seed,
        uint64 problem_area_size,
        uint64 max_circle_radius
    ) internal pure returns (VRFCircle memory) {
        uint256 mask = 0xffffffffffffffff;
        uint64 u_x = uint64(seed & mask);
        uint64 u_y = uint64((seed >> 64) & mask);
        uint64 u_radius = uint64((seed >> 128) & mask);
        uint64 u_carry = uint64((seed >> 192) & mask);

        u_x = u_x ^ u_carry;
        u_y = u_y ^ PCG32RandomLib.i64_rotate_right(u_carry, 24);
        u_radius = u_radius ^ PCG32RandomLib.i64_rotate_right(u_carry, 48);

        return
            VRFCircle({
                x: int64(u_x % problem_area_size),
                y: int64(u_y % problem_area_size),
                radius: int64(u_radius % max_circle_radius)
            });
    }

	function is_circle_in_problem_area(
        int64 cx,
        int64 cy,
        int64 radius,
        int64 problem_area_size
    ) internal pure returns (bool) {
        int64 ext_x = cx + radius;
        int64 ext_y = cy + radius;
        if (
            (cx < radius) ||
            (cy < radius) ||
            (ext_x > problem_area_size) ||
            (ext_y > problem_area_size)
        ) {
            return false;
        }

        return true;
    }

	/**
     * Generate a random test circle that may intersect with the problem circle set
     */
    function generate_rnd_test_circle(
        PCGSha256RandomState memory generator,
        int64 problem_area_size,
        int64 max_circle_radius,
        int64 minradius
    ) internal pure returns (VRFCircle memory) {

        VRFCircle memory new_circle = VRFCircle({
            x: int64(-1),
            y: int64(-1),
            radius: int64(-1)
        });

        uint256 next_seed = PCGSha256RandomLib.next_value_mem(generator);

        while (new_circle.radius < minradius) 
		{
            new_circle = create_circle_rnd_mem(next_seed, uint64(problem_area_size), uint64(max_circle_radius) );
            next_seed = PCGSha256RandomLib.next_value_mem(generator);
        }

        return new_circle;
    }

	function test_circles_intersection(
		int64 cx0, int64 cy0, int64 radius0,
		int64 cx1, int64 cy1, int64 radius1)
		internal pure returns(bool)
	{
		int64 diffvec_x = cx1 - cx0;
		int64 diffvec_y = cy1 - cy0;
		int64 dist_sqr = Fix64Math.mul(diffvec_x, diffvec_x) + Fix64Math.mul(diffvec_y, diffvec_y);

		// calculate squared sum of radius
		int64 sumradius = radius0 + radius1;
		int64 sumradius_sqr = Fix64Math.mul(sumradius, sumradius);
		return sumradius_sqr > dist_sqr;
	}

	function has_intersections_in_problem(
		VRFCircleProblemSnapshot memory problem,
		int64 cx, int64 cy, int64 radius
	) internal pure returns(bool)
	{
		uint256 circle_count = problem.static_circles.length;
        for (uint256 i = 0; i < circle_count; i++)
		{
            VRFCircle memory s_circle = problem.static_circles[i];

            bool bintersects = VRFCircleProblemLib.test_circles_intersection(
				cx, cy, radius,
				s_circle.x, s_circle.y, s_circle.radius
			);

            if (bintersects) {
                // does intersect
                return true;
            }
        }

        return false;
	}


	/**
     * Generate a valid test circle that doesn't intersect with the problem circle set
     */
    function generate_rnd_test_valid_circle(
        PCGSha256RandomState memory generator,
		VRFCircleProblemSnapshot memory problem
    ) internal pure returns (VRFCircle memory) 
	{
        VRFCircle memory new_circle = VRFCircle({x: int64(-1),y: int64(-1),radius: int64(-1)});

        bool isvalid = false;
        int64 problem_area = problem.problem_area_size;
		int64 max_radius = problem.max_circle_radius;
		int64 min_radius = problem.solution_min_radius;

        while (isvalid == false) 
		{
            new_circle = generate_rnd_test_circle(
                generator,
                problem_area,
				max_radius,
                min_radius
            );

            int64 cx = new_circle.x;
            int64 cy = new_circle.y;
            int64 radius = new_circle.radius;
			bool inarea = is_circle_in_problem_area(cx, cy, radius, problem_area);

            if (inarea == true) 
			{
                inarea = has_intersections_in_problem(problem, cx, cy, radius);
                if (inarea == false) 
				{
                    isvalid = true;
                }
            }
        }

        return new_circle;
    }
}



interface IVRFCircleProblem is IERC165
{
	/// Configuration
	function configure(uint256 seed) external;
    function restart_problem() external;

	/// Attributes
	function get_maximum_circle_count() external view returns(uint32);
	function set_maximum_circle_count(uint32 circle_count) external;
	

	function get_problem_area_size() external view returns(int64);
	function set_problem_area_size(int64 area_size) external;

	function get_maximum_circle_radius() external view returns(int64);
	function set_maximum_circle_radius(int64 radius) external;

	function get_solution_min_radius() external view returns(int64);
	function set_solution_min_radius(int64 radius) external;
	
	function get_static_circle_count() external view returns(uint32);	
	function fetch_static_circle(uint32 index) external view returns(VRFCircle memory);

	/// Obtain current random information
	function fetch_random_state() external view returns(PCGSha256RandomState memory);
	function fetch_last_seed() external view returns(uint256);
	/// operations

	/**
	 * Generates a new random number in the internal sequence.
	 * This only could be called by an authorized controller.
	 */
	function next_rnd_number() external returns(uint256);
	
	/**
	 * Test circle against static circles only
	 */
    function has_intersections(int64 cx, int64 cy, int64 cradius) external view returns (bool);

	/**
	 * Test against problem area and static circles
	 */
	function validate_solution(int64 cx, int64 cy, int64 cradius) external view returns (bool);

    /**
     * Returns true when finished
     */
    function insert_new_circle() external returns (bool);
    
    
	function circle_problem_snapshot()
        external
        view
        returns (VRFCircleProblemSnapshot memory);
}




/**
 * Geometric Problem configuration
 */
contract VRFCircleProblem is IVRFCircleProblem, ERC165, DVControlable
{
    // Maximum number of circles of the problem. 16 by default
    uint32 private _max_static_circle_count;

    // current number of circles of the problem. Up to max_static_circle_count
    uint32 private _static_circle_count;

    // Space area size where the circles lie
    int64 private _problem_area_size;

    // Maximum radius of the generated circles
    int64 private _max_circle_radius;

	// For problem solving
	int64 private _solution_min_radius;

	

    PCGSha256RandomState private _rnd_generator;

    /// Pseudo array
    mapping(uint32 => VRFCircle) private _static_circles;

    // call this on contract constructor
    constructor(uint256 seed) {
        _max_static_circle_count = VRF_CIRCLES_COUNT;
        _static_circle_count = 0;
        _problem_area_size = VRF_PROBLEM_AREA;
        _max_circle_radius = VRF_PROBLEM_MAXRADIUS;
		_solution_min_radius = Fix64Math.div(VRF_PROBLEM_MAXRADIUS,10000);

        PCGSha256RandomLib.configure(_rnd_generator, seed);
    }

	function supportsInterface(bytes4 interfaceId) public view virtual override(ERC165, IERC165) returns (bool) {
        return
            interfaceId == type(IVRFCircleProblem).interfaceId ||
            super.supportsInterface(interfaceId);
    }

	/// Configuration

    // call this when generating a new sequence
    function configure(uint256 seed)
        external virtual override onlyOwner
    {
        _static_circle_count = 0;
        PCGSha256RandomLib.configure(_rnd_generator, seed);
    }

    function restart_problem() external virtual override onlyOwner
	{
        _static_circle_count = 0;
    }

	/// Attributes
	function get_maximum_circle_count() external view virtual override returns(uint32)
	{
		return _max_static_circle_count;
	}

	function set_maximum_circle_count(uint32 circle_count) external virtual override onlyOwner
	{
		_max_static_circle_count = circle_count;
	}
	

	function get_problem_area_size() external view  virtual override returns(int64)
	{
		return _problem_area_size;
	}

	function set_problem_area_size(int64 area_size) external virtual override onlyOwner
	{
		_problem_area_size = area_size;
	}

	function get_maximum_circle_radius() external view virtual override returns(int64)
	{
		return _max_circle_radius;
	}

	function set_maximum_circle_radius(int64 radius) external virtual override onlyOwner
	{
		_max_circle_radius = radius;
	}
	
	function get_solution_min_radius() external view virtual override returns(int64)
	{
		return _solution_min_radius;
	}

	function set_solution_min_radius(int64 radius) external virtual override onlyOwner
	{
		_solution_min_radius = radius;
	}

	function get_static_circle_count() external view virtual override returns(uint32)
	{
		return _static_circle_count;
	}

	function fetch_static_circle(uint32 index) external view virtual override returns(VRFCircle memory)
	{
		if(index >= _static_circle_count) return VRFCircle({x:0,y:0, radius:0});
		VRFCircle storage pcircle = _static_circles[index];
		return VRFCircle({x:pcircle.x, y:pcircle.y, radius:pcircle.radius});
	}

	function fetch_random_state() external view virtual override returns(PCGSha256RandomState memory)
	{
		return _rnd_generator;
	}

	function fetch_last_seed() external view virtual override returns(uint256)
	{
		return PCGSha256RandomLib.get_seed256(_rnd_generator);
	}

	/// Operations 

	/**
	 * Random Number generation with registered seed.
	 */
	function next_rnd_number() external virtual override onlyOwner returns(uint256)
	{
		return PCGSha256RandomLib.next_value(_rnd_generator);
	}
	
	/// Internal method
	function _has_intersections(
        int64 cx,
        int64 cy,
        int64 cradius
    ) internal view returns (bool) 
	{
        uint32 circle_count = _static_circle_count;
        for (uint32 i = 0; i < circle_count; i++)
		{
            VRFCircle storage s_circle = _static_circles[i];

            bool bintersects = VRFCircleProblemLib.test_circles_intersection(
				cx, cy, cradius,
				s_circle.x, s_circle.y, s_circle.radius
			);

            if (bintersects) {
                // does intersect
                return true;
            }
        }

        return false;
    }
    
	/**
	 * Check if circle has intersections with static circles.
	 * It doesn't check against problem space area.
	 */
	function has_intersections(
        int64 cx,
        int64 cy,
        int64 cradius
    ) external view virtual override returns (bool) 
	{
		return _has_intersections(cx, cy, cradius);
    }

	/**
	 * Test agaisnt problem area and static circles
	 */
	function validate_solution(
		int64 cx, int64 cy, int64 cradius
	) external view virtual override returns (bool)
	{
		if(cradius < _solution_min_radius) return false;

		bool inarea = VRFCircleProblemLib.is_circle_in_problem_area(cx, cy, cradius, _problem_area_size);
		if(inarea == false) return false;

		bool bintersects = _has_intersections(cx, cy, cradius);
		return bintersects == false;
	}

    /**
     * Returns true when finished
     */
    function insert_new_circle()
        external virtual override onlyOwner
        returns (bool)
    {
        uint32 curr_index = _static_circle_count;
        uint32 top_count = _max_static_circle_count;
        if (top_count <= curr_index) return true; // finished here

        uint256 next_seed = PCGSha256RandomLib.next_value(_rnd_generator);

        VRFCircle storage new_circle = _static_circles[curr_index];

        VRFCircleProblemLib.create_circle_rnd(
            new_circle,
            next_seed,
            uint64(_problem_area_size),
            uint64(_max_circle_radius)
        );

        bool hascollision = _has_intersections(
            new_circle.x,
            new_circle.y,
            new_circle.radius
        );

        if (hascollision) 
		{
            return false; // not ready yet
        }

        // commit new member
        curr_index++;
        _static_circle_count = curr_index;

        return curr_index >= top_count; // has finished
    }

	function circle_problem_snapshot()
        external view virtual override
        returns (VRFCircleProblemSnapshot memory)
	{
		uint32 numcircles = _static_circle_count;
        VRFCircleProblemSnapshot memory retsnapshot = VRFCircleProblemSnapshot({
            problem_area_size: _problem_area_size,
			max_circle_radius: _max_circle_radius,
			solution_min_radius: _solution_min_radius,
            static_circles: new VRFCircle[](numcircles)
        });

        for (uint32 i = 0; i < numcircles; i += 1) {
            retsnapshot.static_circles[i] = _static_circles[i];
        }

        return retsnapshot;		
	}
}

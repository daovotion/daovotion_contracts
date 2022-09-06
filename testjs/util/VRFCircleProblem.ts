import { BigNumber, ethers} from "ethers";
import { pcg32random, pcgsha256random } from "./PCGRandom";
import { fix64 } from "./FixMath";

namespace simulation
{

	export class VRFCircle
	{
		x:bigint;
		y:bigint;
		radius:bigint;

		constructor(_x:bigint = BigInt(0), _y:bigint = BigInt(0), _radius:bigint = BigInt(-1))
		{
			this.x = BigInt(_x.toString());
			this.y = BigInt(_y.toString());
			this.radius = BigInt(_radius.toString());
		}

		is_valid()
		{
			return this.radius > BigInt(0);
		}

		public test_collision(other:VRFCircle):boolean
		{
			let diffx = this.x - other.x;
			let diffy = this.y - other.y;
			let dist_sqr = fix64.mul(diffx, diffx) + fix64.mul(diffy, diffy);
			let radius_sum = this.radius + other.radius;

			return (fix64.mul(radius_sum, radius_sum) > dist_sqr) as boolean;
		}

		public is_circle_in_problem_area(problem_area_size:bigint):boolean
		{
			let cx = this.x;
			let cy = this.y;
			let cradius = this.radius;

			let ext_x = cx + cradius;
			let ext_y = cy + cradius;
			if (
				(cx < cradius) ||
				(cy < cradius) ||
				(ext_x > problem_area_size) ||
				(ext_y > problem_area_size)
			)
			{
				return false;
			}

			return true;
		}

		public from_random(rnd_number:bigint, problem_area_size:bigint, max_circle_radius:bigint)
		{
			const mask:bigint = BigInt("0xffffffffffffffff");
			
			let u_x = rnd_number & mask;
			let u_y = (rnd_number >> BigInt(64)) & mask;
			let u_radius = (rnd_number >> BigInt(128)) & mask;
			let u_carry = (rnd_number >> BigInt(192)) & mask;

			u_x = u_x ^ u_carry;
			u_y = u_y ^ pcg32random.i64_rotate_right(u_carry, 24n);
			u_radius = u_radius ^ pcg32random.i64_rotate_right(u_carry, 48n);

			this.x = u_x % problem_area_size;
			this.y = u_y % problem_area_size;
			this.radius = u_radius % max_circle_radius;
		}

        public toString():string
        {
            return `{x:${this.x.toString()}, y:${this.y.toString()}, radius:${this.radius.toString()}}`;
        }
	}

	export interface IValidCircleParams
	{
		circle:VRFCircle;
		rng_seed:bigint;
		num_iterations:number;
	}

	export interface IVRFProblemWork
	{
		rng_seed:bigint;
		num_iterations:number;
	}

	export class VRFCircleProblem
	{
		problem_area_size:bigint;	
		max_circle_radius:bigint;
		solution_min_radius:bigint;	
		static_circles:Array<VRFCircle>;

		constructor()
		{
			this.problem_area_size = BigInt("0x80000000000");// 2048.00 fix32
			this.max_circle_radius = this.problem_area_size >> BigInt(1);
			this.solution_min_radius = BigInt("0x8000");
			this.static_circles = new Array<VRFCircle>();
		}

		public circle_count():number
		{
			return this.static_circles.length;
		}

        public reset_problem()
        {
            this.static_circles.length = 0;
        }

		public has_intersections(test_circle:VRFCircle):boolean
		{
			for(let vcircle of this.static_circles)
			{
				if(test_circle.test_collision(vcircle))
				{
					return true;
				}
			}

			return false;
		}

		public is_circle_in_problem_area(test_circle:VRFCircle):boolean
		{
			return test_circle.is_circle_in_problem_area(this.problem_area_size);
		}

		/**
		 * Attempts to insert a new random circle, if it does fit into the problem space.
		 * It may create a circle or not, so the client has to check the problem fulfillment with the circle_count() method.
		 * @param rng_seed 
		 * @returns The updated RNG seed (BigInt)
		 */
		public insert_static_circle(rng_seed:bigint):bigint
		{
			let rnd_params = pcgsha256random.next_value(rng_seed);

			let new_circle = new VRFCircle();
			new_circle.from_random(rnd_params.rnd_number, this.problem_area_size, this.max_circle_radius);

			if(this.has_intersections(new_circle) == false)
			{
				// insert into problem
				this.static_circles.push(new_circle);
			}

			return rnd_params.seed_rng;
		}

		public generate_static_circles(required_circles:number, max_iterations:number, _rng_seed:bigint):IVRFProblemWork
		{
            this.reset_problem();
            
			let num_iterations = 0;
			let new_seed = BigInt(_rng_seed);
			while(this.static_circles.length < required_circles && num_iterations < max_iterations)
			{
				new_seed = this.insert_static_circle(new_seed);
				num_iterations++;
			}

			return {rng_seed:new_seed, num_iterations:num_iterations};
		}

		public is_valid_solution(test_circle:VRFCircle):boolean
		{
			if(test_circle.radius < this.solution_min_radius) return false;
			if(this.is_circle_in_problem_area(test_circle) == false) return false;
			return this.has_intersections(test_circle) == false;		
		}

		public generate_test_circle(rng_seed:bigint, max_iterations:number):IValidCircleParams
		{
			let gen_circle = new VRFCircle();
			let num_iterations = 1;			
			let rnd_params = pcgsha256random.next_value(rng_seed);
			while(num_iterations <= max_iterations)
			{
				if(pcgsha256random.debug_print_rng_bytes_generation)
				{
					console.log("rnd=",BigNumber.from(rnd_params.seed_rng).toHexString());
				}
				
				
				gen_circle.from_random(rnd_params.rnd_number, this.problem_area_size, this.max_circle_radius);

				if(this.is_valid_solution(gen_circle))
				{
					return {circle:gen_circle, rng_seed:rnd_params.seed_rng, num_iterations:num_iterations};
				}

				rnd_params = pcgsha256random.next_value(rnd_params.seed_rng);
				num_iterations++;
			}

			return {circle:gen_circle, rng_seed:rnd_params.seed_rng, num_iterations:num_iterations};
		}

		public config_from_snapshot(snapshot:any)
		{
			this.static_circles.length = 0;
			if(Array.isArray(snapshot) == false)
			{
				throw Error("Malformed problem snapshot, bad parameters");
			}

			if(snapshot.length < 4 || Array.isArray(snapshot[3]) == false)
			{
				throw Error("Malformed problem snapshot, bad parameters");
			}

			this.problem_area_size = BigNumber.from(snapshot[0]).toBigInt();
			this.max_circle_radius = BigNumber.from(snapshot[1]).toBigInt();
			this.solution_min_radius = BigNumber.from(snapshot[2]).toBigInt();

			const arr = snapshot[3];
			this.static_circles.length = arr.length;
			for(let i = 0; i < arr.length; i++)
			{
				const vc = arr[i];
				let newcircle = new VRFCircle(
					BigNumber.from(vc[0]).toBigInt(),
					BigNumber.from(vc[1]).toBigInt(),
					BigNumber.from(vc[2]).toBigInt()
				);

				this.static_circles[i] = newcircle;
			}
		}

		public toString():string
		{
			let output_fields = `{
	problem_area_size:${this.problem_area_size.toString()},
	max_circle_radius:${this.max_circle_radius.toString()},
	solution_min_radius:${this.solution_min_radius.toString()},
	static_circles:[
			`;
			for(let vc of this.static_circles)
			{
				output_fields += vc.toString();
			}

			return output_fields + "\n]}";
		}
	}

} // end namespace simulation

export {simulation}

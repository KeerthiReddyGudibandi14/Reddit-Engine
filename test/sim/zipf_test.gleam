import gleeunit
import gleeunit/should
import sim/zipf
import gleam/float

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn probabilities_sum_to_one_test() {
  let assert Ok(sampler) = zipf.build(20, 1.2)
  let total = sampler |> zipf.probabilities |> float.sum
  should.be_true(float.absolute_value(total -. 1.0) <. 0.000_1)
}


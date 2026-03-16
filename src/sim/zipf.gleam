import gleam/float
import gleam/int
import gleam/list

/// Zipf sampler supporting Reddit-like rank distributions.
///
/// See https://en.wikipedia.org/wiki/Zipf's_law for background.
pub type ZipfSampler {
  ZipfSampler(
    size: Int,
    exponent: Float,
    cdf: List(Float),
    probabilities: List(Float),
  )
}

pub type ZipfError {
  InvalidSize
  InvalidExponent
  RankOutOfBounds
}

pub fn build(size: Int, exponent: Float) -> Result(ZipfSampler, ZipfError) {
  case size > 0, exponent >. 0.0 {
    True, True -> {
      let normalization = harmonic(size, exponent)
      let probabilities =
        list.range(1, size + 1)
        |> list.map(fn(rank) { probability(rank, exponent, normalization) })
      let cdf = cumulative(probabilities)
      Ok(ZipfSampler(
        size: size,
        exponent: exponent,
        cdf: cdf,
        probabilities: probabilities,
      ))
    }

    False, _ -> Error(InvalidSize)
    _, False -> Error(InvalidExponent)
  }
}

pub fn sample(sampler: ZipfSampler, u: Float) -> Int {
  let clamped = float.clamp(u, 0.0, 0.999_999)
  sample_loop(sampler.cdf, clamped, 1, sampler.size)
}

pub fn probability_for(
  sampler: ZipfSampler,
  rank: Int,
) -> Result(Float, ZipfError) {
  case rank < 1 {
    True -> Error(RankOutOfBounds)
    False ->
      case list.drop(sampler.probabilities, rank - 1) {
        [] -> Error(RankOutOfBounds)
        [value, .._] -> Ok(value)
      }
  }
}

pub fn size(sampler: ZipfSampler) -> Int {
  sampler.size
}

pub fn probabilities(sampler: ZipfSampler) -> List(Float) {
  sampler.probabilities
}

fn harmonic(size: Int, exponent: Float) -> Float {
  list.range(1, size + 1)
  |> list.map(fn(rank) { term(rank, exponent) })
  |> float.sum
}

fn probability(rank: Int, exponent: Float, normalization: Float) -> Float {
  term(rank, exponent) /. normalization
}

fn term(rank: Int, exponent: Float) -> Float {
  let neg_exp = float.negate(exponent)
  case float.power(int.to_float(rank), neg_exp) {
    Ok(value) -> value
    Error(_) -> 0.0
  }
}

fn cumulative(values: List(Float)) -> List(Float) {
  cumulative_loop(values, 0.0, [])
  |> list.reverse
}

fn cumulative_loop(
  values: List(Float),
  total: Float,
  acc: List(Float),
) -> List(Float) {
  case values {
    [] -> acc
    [head, ..tail] -> {
      let next_total = total +. head
      cumulative_loop(tail, next_total, [next_total, ..acc])
    }
  }
}

fn sample_loop(
  cdf: List(Float),
  target: Float,
  rank: Int,
  max_rank: Int,
) -> Int {
  case cdf {
    [] -> max_rank
    [head, ..tail] -> case target <=. head {
      True -> rank
      False -> sample_loop(tail, target, rank + 1, max_rank)
    }
  }
}


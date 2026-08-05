module Eval
  # Pure scoring: given the rank (1-indexed) at which each question's expected
  # chunk appeared in a strategy's results, or nil if it never appeared within
  # the top-K, computes that strategy's hit rate and mean reciprocal rank.
  module HitRateMrr
    def self.score(ranks)
      return { hit_rate: 0.0, mrr: 0.0 } if ranks.empty?

      hits = ranks.count { |rank| rank }
      reciprocal_sum = ranks.sum { |rank| rank ? 1.0 / rank : 0.0 }

      { hit_rate: hits.to_f / ranks.size, mrr: reciprocal_sum / ranks.size }
    end
  end
end

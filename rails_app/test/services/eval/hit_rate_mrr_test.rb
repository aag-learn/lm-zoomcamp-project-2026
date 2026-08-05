require "test_helper"

module Eval
  class HitRateMrrTest < ActiveSupport::TestCase
    test "a rank-1 hit scores hit_rate 1.0 and mrr 1.0" do
      result = HitRateMrr.score([ 1 ])

      assert_equal 1.0, result[:hit_rate]
      assert_equal 1.0, result[:mrr]
    end

    test "a rank-4 hit contributes 0.25 to mrr but still counts as a hit" do
      result = HitRateMrr.score([ 4 ])

      assert_equal 1.0, result[:hit_rate]
      assert_in_delta 0.25, result[:mrr], 0.0001
    end

    test "a miss (nil rank) contributes zero to both hit_rate and mrr" do
      result = HitRateMrr.score([ nil ])

      assert_equal 0.0, result[:hit_rate]
      assert_equal 0.0, result[:mrr]
    end

    test "mixed hits and misses average correctly across questions" do
      result = HitRateMrr.score([ 1, nil, 2 ])

      assert_in_delta 2.0 / 3, result[:hit_rate], 0.0001
      assert_in_delta (1.0 + 0 + 0.5) / 3, result[:mrr], 0.0001
    end

    test "an empty set of ranks scores zero rather than raising" do
      result = HitRateMrr.score([])

      assert_equal 0.0, result[:hit_rate]
      assert_equal 0.0, result[:mrr]
    end
  end
end

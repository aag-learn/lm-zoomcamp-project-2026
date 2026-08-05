module Eval
  # Scores keyword-only, vector-only, hybrid, and hybrid+rerank retrieval
  # against the full ground-truth set, searched over the entire ingested
  # corpus (not just the named modules) — see design.md.
  class RetrievalEvaluator
    STRATEGIES = %i[keyword vector hybrid hybrid_rerank].freeze
    TOP_K = 8 # matches SearchAnsibleDocs::RESULT_LIMIT, the live app's real top-K

    def self.call(ground_truth: GroundTruth.load, top_k: TOP_K)
      new(ground_truth, top_k).call
    end

    def initialize(ground_truth, top_k)
      @ground_truth = ground_truth
      @top_k = top_k
    end

    def call
      STRATEGIES.index_with do |strategy|
        Rails.logger.info("[Eval::RetrievalEvaluator] scoring #{strategy} against #{@ground_truth.size} questions")
        score_strategy(strategy)
      end
    end

    private

    def score_strategy(strategy)
      total = @ground_truth.size

      ranks = @ground_truth.each_with_index.map do |row, index|
        if strategy == :hybrid_rerank
          Rails.logger.info("[Eval::RetrievalEvaluator] hybrid_rerank #{index + 1}/#{total} #{row[:question]}")
        end

        rank_of_expected(strategy, row)
      end

      HitRateMrr.score(ranks)
    end

    def rank_of_expected(strategy, row)
      stable_ids = retrieve(strategy, row[:question])
      index = stable_ids.index(row[:stable_id])
      index && index + 1
    end

    def retrieve(strategy, query)
      case strategy
      when :keyword
        Retrieval::KeywordSearch.call(query).limit(@top_k).map(&:stable_id)
      when :vector
        Retrieval::VectorSearch.call(query, limit: @top_k).map(&:stable_id)
      when :hybrid
        Retrieval::HybridSearch.call(query).first(@top_k).map { |scored| scored.chunk.stable_id }
      when :hybrid_rerank
        hybrid_rerank_stable_ids(query)
      end
    end

    def hybrid_rerank_stable_ids(query)
      scored = Retrieval::HybridSearch.call(query)
      return [] if scored.empty?

      rerank_scores = RerankerClient.rerank(query: query, candidates: scored.map { |s| s.chunk.content })
      scored.zip(rerank_scores)
            .sort_by { |(_scored_chunk, rerank_score)| -rerank_score }
            .first(@top_k)
            .map { |(scored_chunk, _rerank_score)| scored_chunk.chunk.stable_id }
    end
  end
end

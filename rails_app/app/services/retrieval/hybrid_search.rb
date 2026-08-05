module Retrieval
  class HybridSearch
    K = 60
    LIMIT = 20

    def self.call(query, scope: Chunk.all, limit: LIMIT)
      keyword_ranked = Retrieval::KeywordSearch.call(query, scope: scope).to_a
      vector_ranked = Retrieval::VectorSearch.call(query, scope: scope, limit: limit).to_a

      scores = Hash.new(0.0)
      chunks_by_id = {}

      [ keyword_ranked, vector_ranked ].each do |ranked|
        ranked.each_with_index do |chunk, index|
          scores[chunk.id] += 1.0 / (K + index + 1)
          chunks_by_id[chunk.id] = chunk
        end
      end

      scores.sort_by { |_id, score| -score }.first(limit).map do |chunk_id, score|
        ScoredChunk.new(chunks_by_id.fetch(chunk_id), score)
      end
    end
  end
end

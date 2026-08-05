module Retrieval
  class VectorSearch
    LIMIT = 20

    def self.call(query, scope: Chunk.all, limit: LIMIT)
      embedding = EmbeddingClient.embed([ query ]).first
      scope.nearest_neighbors(:embedding, embedding, distance: "cosine").limit(limit)
    end
  end
end

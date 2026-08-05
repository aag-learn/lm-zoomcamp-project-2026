module Retrieval
  class KeywordSearch
    def self.call(query, scope: Chunk.all)
      scope.search(query)
    end
  end
end

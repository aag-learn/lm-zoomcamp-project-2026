class SearchAnsibleDocs < RubyLLM::Tool
  description "Search the ingested Ansible module documentation for relevant parameters, " \
              "examples, and return values, using hybrid keyword+semantic search with reranking."
  param :query, desc: "The search query, in natural language or Ansible terminology."
  param :module_filter,
        desc: "Optional fully-qualified module name to restrict the search to (e.g. ansible.builtin.copy).",
        required: false

  CANDIDATE_LIMIT = 20
  RESULT_LIMIT = 8

  attr_reader :retrieved_chunks, :last_call_top_module

  def initialize
    super()
    @retrieved_chunks = []
    @last_call_top_module = nil
  end

  def execute(query:, module_filter: nil)
    scope = module_filter.present? ? Chunk.joins(:ansible_module).where(ansible_module: { fqcn: module_filter }) : Chunk.all

    scored = Retrieval::HybridSearch.call(query, scope: scope, limit: CANDIDATE_LIMIT)
    return "No results found." if scored.empty?

    rerank_scores = RerankerClient.rerank(query: query, candidates: scored.map { |s| s.chunk.content })
    ranked = scored.zip(rerank_scores).sort_by { |(_scored_chunk, rerank_score)| -rerank_score }.first(RESULT_LIMIT)

    ranked.each do |scored_chunk, rerank_score|
      retrieved_chunks << {
        stable_id: scored_chunk.chunk.stable_id,
        rrf_score: scored_chunk.rrf_score,
        rerank_score: rerank_score
      }
    end
    @last_call_top_module = ranked.first&.first&.chunk&.ansible_module&.fqcn

    ranked.map { |scored_chunk, _rerank_score| "#{scored_chunk.chunk.stable_id}:\n#{scored_chunk.chunk.content}" }
          .join("\n\n---\n\n")
  end
end

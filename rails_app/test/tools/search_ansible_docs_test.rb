require "test_helper"

class SearchAnsibleDocsTest < ActiveSupport::TestCase
  QUERY = "copy files to a remote host"

  setup do
    @copy = create_module("ansible.builtin.copy")
    @uri = create_module("ansible.builtin.uri")

    @copy_src = create_chunk(
      ansible_module: @copy,
      stable_id: "ansible.builtin.copy::param::src",
      content: captured_embeddings.fetch("ansible.builtin.copy::param::src").fetch("text"),
      embedding: captured_embedding_for("ansible.builtin.copy::param::src")
    )
    @uri_dest = create_chunk(
      ansible_module: @uri,
      stable_id: "ansible.builtin.uri::param::dest",
      content: captured_embeddings.fetch("ansible.builtin.uri::param::dest").fetch("text"),
      embedding: captured_embedding_for("ansible.builtin.uri::param::dest")
    )

    stub_request(:post, "http://embedder:8000/embed")
      .with(body: { texts: [ QUERY ] }.to_json)
      .to_return(
        status: 200,
        body: { embeddings: [ captured_embedding_for("query:#{QUERY}") ] }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    # Reranker reverses the hybrid order, so we can tell reranking actually ran
    # (rather than the tool just passing hybrid order straight through).
    stub_request(:post, "http://embedder:8000/rerank").to_return do |request|
      body = JSON.parse(request.body)
      scores = body["candidates"].each_index.map { |i| i.to_f }
      { status: 200, body: { scores: scores }.to_json, headers: { "Content-Type" => "application/json" } }
    end
  end

  test "returns results and accumulates retrieved chunks with both scores" do
    tool = SearchAnsibleDocs.new

    result = tool.execute(query: QUERY)

    assert_includes result, "ansible.builtin.copy::param::src"
    assert_equal 2, tool.retrieved_chunks.size
    entry = tool.retrieved_chunks.find { |c| c[:stable_id] == "ansible.builtin.copy::param::src" }
    assert entry
    assert entry[:rrf_score].is_a?(Numeric)
    assert entry[:rerank_score].is_a?(Numeric)
  end

  test "module_filter narrows results to one module" do
    tool = SearchAnsibleDocs.new

    tool.execute(query: QUERY, module_filter: "ansible.builtin.copy")

    stable_ids = tool.retrieved_chunks.map { |c| c[:stable_id] }
    assert_includes stable_ids, "ansible.builtin.copy::param::src"
    assert_not_includes stable_ids, "ansible.builtin.uri::param::dest"
  end

  test "accumulates retrieved chunks across multiple calls on the same instance" do
    tool = SearchAnsibleDocs.new

    tool.execute(query: QUERY, module_filter: "ansible.builtin.copy")
    tool.execute(query: QUERY, module_filter: "ansible.builtin.uri")

    stable_ids = tool.retrieved_chunks.map { |c| c[:stable_id] }
    assert_includes stable_ids, "ansible.builtin.copy::param::src"
    assert_includes stable_ids, "ansible.builtin.uri::param::dest"
  end
end

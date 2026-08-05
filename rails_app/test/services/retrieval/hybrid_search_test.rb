require "test_helper"

module Retrieval
  class HybridSearchTest < ActiveSupport::TestCase
    QUERY = "copy files to a remote host"

    setup do
      @copy = create_module("ansible.builtin.copy")
      @uri = create_module("ansible.builtin.uri")
      @unarchive = create_module("ansible.builtin.unarchive")
      @user = create_module("ansible.builtin.user")

      # copy::src and copy::dest both contain "copy"/"remote" (keyword match)
      # AND have real embeddings close to the query (vector match).
      @copy_src = create_chunk(
        ansible_module: @copy,
        stable_id: "ansible.builtin.copy::param::src",
        content: captured_embeddings.fetch("ansible.builtin.copy::param::src").fetch("text"),
        embedding: captured_embedding_for("ansible.builtin.copy::param::src")
      )
      @copy_dest = create_chunk(
        ansible_module: @copy,
        stable_id: "ansible.builtin.copy::param::dest",
        content: captured_embeddings.fetch("ansible.builtin.copy::param::dest").fetch("text"),
        embedding: captured_embedding_for("ansible.builtin.copy::param::dest")
      )

      # unarchive::src contains "copy" but not "remote" — weaker keyword match, present.
      @unarchive_src = create_chunk(
        ansible_module: @unarchive,
        stable_id: "ansible.builtin.unarchive::param::src",
        content: captured_embeddings.fetch("ansible.builtin.unarchive::param::src").fetch("text"),
        embedding: captured_embedding_for("ansible.builtin.unarchive::param::src")
      )

      # uri::dest has NO "copy"/"remote" keyword overlap at all (excluded entirely by
      # keyword search's WHERE clause) but has a real embedding meaningfully close to
      # the query — this is the case that proves vector search adds signal keyword
      # search alone would have missed.
      @uri_dest = create_chunk(
        ansible_module: @uri,
        stable_id: "ansible.builtin.uri::param::dest",
        content: captured_embeddings.fetch("ansible.builtin.uri::param::dest").fetch("text"),
        embedding: captured_embedding_for("ansible.builtin.uri::param::dest")
      )

      # Unrelated to the query in both keyword and vector terms.
      @user_shell = create_chunk(
        ansible_module: @user,
        stable_id: "ansible.builtin.user::param::shell",
        content: captured_embeddings.fetch("ansible.builtin.user::param::shell").fetch("text"),
        embedding: captured_embedding_for("ansible.builtin.user::param::shell")
      )

      stub_request(:post, "http://embedder:8000/embed")
        .with(body: { texts: [ QUERY ] }.to_json)
        .to_return(
          status: 200,
          body: { embeddings: [ captured_embedding_for("query:#{QUERY}") ] }.to_json,
          headers: { "Content-Type" => "application/json" }
        )
    end

    test "keyword search alone would have excluded uri::dest entirely" do
      # Sanity check on the fixture itself: confirms the test scenario actually
      # exercises the case we care about, rather than accidentally not.
      assert_not_includes Retrieval::KeywordSearch.call(QUERY), @uri_dest
    end

    test "merges keyword and vector results, surfacing chunks keyword search alone would miss" do
      results = Retrieval::HybridSearch.call(QUERY)

      chunks = results.map(&:chunk)
      assert_includes chunks, @uri_dest, "vector search should have surfaced uri::dest even though keyword search excluded it"
    end

    test "the module strong in both keyword and vector rankings ranks at the top" do
      # Both copy::src and copy::dest are strongly relevant on both axes; which of
      # the two edges out first is sensitive to ts_rank's exact scoring, not
      # something to hard-code — the robust, meaningful claim is that the right
      # *module* wins, not which of two similarly-relevant chunks from it does.
      results = Retrieval::HybridSearch.call(QUERY)

      assert_equal @copy.id, results.first.chunk.ansible_module_id
    end

    test "each result carries its RRF score" do
      results = Retrieval::HybridSearch.call(QUERY)

      assert results.all? { |r| r.is_a?(Retrieval::ScoredChunk) }
      assert results.all? { |r| r.rrf_score.is_a?(Numeric) && r.rrf_score.positive? }
      assert_equal results.map(&:rrf_score), results.map(&:rrf_score).sort.reverse
    end

    test "scope narrows results to one module" do
      results = Retrieval::HybridSearch.call(QUERY, scope: @copy.chunks)
      chunks = results.map(&:chunk)

      assert_includes chunks, @copy_src
      assert_not_includes chunks, @uri_dest
      assert_not_includes chunks, @user_shell
    end
  end
end

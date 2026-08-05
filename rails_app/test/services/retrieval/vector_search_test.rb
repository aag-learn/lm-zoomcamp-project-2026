require "test_helper"

module Retrieval
  class VectorSearchTest < ActiveSupport::TestCase
    QUERY = "copy files to a remote host"

    setup do
      @copy = create_module("ansible.builtin.copy")
      @uri = create_module("ansible.builtin.uri")
      @user = create_module("ansible.builtin.user")

      @copy_src = create_chunk(
        ansible_module: @copy,
        stable_id: "ansible.builtin.copy::param::src",
        content: "src content",
        embedding: captured_embedding_for("ansible.builtin.copy::param::src")
      )
      @uri_dest = create_chunk(
        ansible_module: @uri,
        stable_id: "ansible.builtin.uri::param::dest",
        content: "uri dest content",
        embedding: captured_embedding_for("ansible.builtin.uri::param::dest")
      )
      @user_shell = create_chunk(
        ansible_module: @user,
        stable_id: "ansible.builtin.user::param::shell",
        content: "shell content",
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

    test "a semantically related chunk ranks above an unrelated one" do
      results = Retrieval::VectorSearch.call(QUERY).to_a

      copy_index = results.index(@copy_src)
      user_index = results.index(@user_shell)

      assert copy_index, "expected copy_src to be present in results"
      assert user_index, "expected user_shell to be present in results"
      assert_operator copy_index, :<, user_index
    end

    test "scope narrows results to one module" do
      results = Retrieval::VectorSearch.call(QUERY, scope: @copy.chunks).to_a

      assert_includes results, @copy_src
      assert_not_includes results, @uri_dest
      assert_not_includes results, @user_shell
    end
  end
end

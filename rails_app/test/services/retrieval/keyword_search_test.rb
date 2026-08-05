require "test_helper"

module Retrieval
  class KeywordSearchTest < ActiveSupport::TestCase
    setup do
      @copy = create_module("ansible.builtin.copy")
      @user = create_module("ansible.builtin.user")

      @copy_src = create_chunk(
        ansible_module: @copy,
        stable_id: "ansible.builtin.copy::param::src",
        content: captured_embedding_text("ansible.builtin.copy::param::src")
      )
      @copy_dest = create_chunk(
        ansible_module: @copy,
        stable_id: "ansible.builtin.copy::param::dest",
        content: captured_embedding_text("ansible.builtin.copy::param::dest")
      )
      @user_shell = create_chunk(
        ansible_module: @user,
        stable_id: "ansible.builtin.user::param::shell",
        content: captured_embedding_text("ansible.builtin.user::param::shell")
      )
    end

    def captured_embedding_text(key)
      captured_embeddings.fetch(key).fetch("text")
    end

    test "finds chunks matching a keyword query" do
      results = Retrieval::KeywordSearch.call("copy remote server")

      assert_includes results, @copy_src
      assert_not_includes results, @user_shell
    end

    test "scope narrows results to one module" do
      results = Retrieval::KeywordSearch.call("path", scope: @copy.chunks)

      assert_includes results, @copy_src
      assert_includes results, @copy_dest
      assert_not_includes results, @user_shell
    end
  end
end

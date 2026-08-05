require "test_helper"

module Ingestion
  class ChunkerTest < ActiveSupport::TestCase
    def raw_doc_fixture(name)
      path = Rails.root.join("test/fixtures/files/ansible_doc/#{name}.json")
      JSON.parse(File.read(path)).values.first
    end

    test "produces exactly one overview chunk" do
      chunks = Chunker.call("ansible.builtin.copy", raw_doc_fixture("copy"))

      overview_chunks = chunks.select { |c| c[:chunk_type] == "overview" }

      assert_equal 1, overview_chunks.size
      assert_equal "ansible.builtin.copy::overview", overview_chunks.first[:stable_id]
      assert_includes overview_chunks.first[:content], "copy"
    end

    test "produces one parameter chunk per option" do
      raw_doc = raw_doc_fixture("copy")
      chunks = Chunker.call("ansible.builtin.copy", raw_doc)

      parameter_chunks = chunks.select { |c| c[:chunk_type] == "parameter" }

      assert_equal raw_doc["doc"]["options"].size, parameter_chunks.size
      assert_includes parameter_chunks.map { |c| c[:stable_id] }, "ansible.builtin.copy::param::mode"
    end

    test "flattens suboptions into the parent parameter chunk instead of producing separate chunks" do
      raw_doc = raw_doc_fixture("iptables")
      chunks = Chunker.call("ansible.builtin.iptables", raw_doc)

      parameter_chunks = chunks.select { |c| c[:chunk_type] == "parameter" }

      # one parameter chunk per top-level option, including tcp_flags itself —
      # not one per suboption (flags, flags_set)
      assert_equal raw_doc["doc"]["options"].size, parameter_chunks.size

      tcp_flags_chunk = parameter_chunks.find { |c| c[:stable_id] == "ansible.builtin.iptables::param::tcp_flags" }
      assert tcp_flags_chunk
      assert_includes tcp_flags_chunk[:content], "flags_set"
    end

    test "produces one example chunk per named example, not one per module" do
      raw_doc = raw_doc_fixture("uri")
      chunks = Chunker.call("ansible.builtin.uri", raw_doc)

      example_chunks = chunks.select { |c| c[:chunk_type] == "example" }

      assert_equal 14, example_chunks.size
      assert_equal "ansible.builtin.uri::example::1", example_chunks.first[:stable_id]
      assert_equal "ansible.builtin.uri::example::14", example_chunks.last[:stable_id]

      # none of the individual example chunks should be anywhere near the full
      # 4041-char block — that's the truncation bug this splitting fixes
      example_chunks.each do |chunk|
        assert_operator chunk[:content].length, :<, 2000
      end
    end

    test "produces one return chunk per return value" do
      raw_doc = raw_doc_fixture("copy")
      chunks = Chunker.call("ansible.builtin.copy", raw_doc)

      return_chunks = chunks.select { |c| c[:chunk_type] == "return" }

      assert_equal raw_doc["return"].size, return_chunks.size
      assert_includes return_chunks.map { |c| c[:stable_id] }, "ansible.builtin.copy::return::backup_file"
    end

    test "falls back to a single example chunk when the examples block does not parse as a list" do
      raw_doc = raw_doc_fixture("copy")
      raw_doc["examples"] = "just a plain string, not YAML list content"

      chunks = Chunker.call("ansible.builtin.copy", raw_doc)
      example_chunks = chunks.select { |c| c[:chunk_type] == "example" }

      assert_equal 1, example_chunks.size
      assert_equal "ansible.builtin.copy::example::1", example_chunks.first[:stable_id]
      assert_includes example_chunks.first[:content], "just a plain string"
    end

    test "falls back to a single example chunk when the examples block is not valid YAML" do
      raw_doc = raw_doc_fixture("copy")
      raw_doc["examples"] = "- name: unterminated\n    foo: [1, 2\n"

      chunks = Chunker.call("ansible.builtin.copy", raw_doc)
      example_chunks = chunks.select { |c| c[:chunk_type] == "example" }

      assert_equal 1, example_chunks.size
      assert_equal "ansible.builtin.copy::example::1", example_chunks.first[:stable_id]
    end

    test "produces no example chunks when there are no examples" do
      raw_doc = raw_doc_fixture("copy")
      raw_doc["examples"] = nil

      chunks = Chunker.call("ansible.builtin.copy", raw_doc)
      example_chunks = chunks.select { |c| c[:chunk_type] == "example" }

      assert_equal 0, example_chunks.size
    end

    test "overview chunk states deprecation status and alternative module for a deprecated module" do
      raw_doc = raw_doc_fixture("apt_key")
      # apt_key's real notes/seealso already happen to mention "deprecated" and
      # deb822_repository in prose — blank them so this assertion can only pass
      # via the structured `deprecated` field itself being surfaced.
      raw_doc["doc"]["notes"] = []
      raw_doc["doc"]["seealso"] = []

      chunks = Chunker.call("ansible.builtin.apt_key", raw_doc)
      overview_chunk = chunks.find { |c| c[:chunk_type] == "overview" }

      assert_includes overview_chunk[:content], "deprecated"
      assert_includes overview_chunk[:content], "ansible.builtin.deb822_repository"
    end

    test "overview chunk contains no deprecation text for a module that isn't deprecated" do
      raw_doc = raw_doc_fixture("copy")
      chunks = Chunker.call("ansible.builtin.copy", raw_doc)

      overview_chunk = chunks.find { |c| c[:chunk_type] == "overview" }

      refute_includes overview_chunk[:content].downcase, "deprecat"
    end
  end
end

require "test_helper"

module Eval
  class GroundTruthGeneratorTest < ActiveSupport::TestCase
    # Never let this test suite write to the real data/ground_truth.csv
    # (Eval::GroundTruth::DEFAULT_PATH) — a per-test tmp path keeps a real,
    # deliberately-generated file from being clobbered by a test run.
    def setup
      @tmp_csv = Tempfile.new([ "ground_truth", ".csv" ])
    end

    def teardown
      @tmp_csv.close!
    end

    def new_generator
      GroundTruthGenerator.new(path: @tmp_csv.path)
    end

    def raw_doc_fixture(name)
      path = Rails.root.join("test/fixtures/files/ansible_doc/#{name}.json")
      JSON.parse(File.read(path)).values.first
    end

    def create_named_module(fqcn, fixture_name)
      raw_doc = raw_doc_fixture(fixture_name)
      AnsibleModule.create!(
        fqcn: fqcn,
        ansible_core_version: "2.21.2",
        deprecated: raw_doc["doc"].key?("deprecated"),
        raw_doc: raw_doc
      )
    end

    test "warns and continues when a named module is missing from the ingested corpus" do
      create_named_module("ansible.builtin.copy", "copy")
      # deliberately not creating apt_key/service/apt/user/iptables

      stub_openai_structured_response("questions" => [ "question one", "question two" ])

      generator = new_generator
      rows = generator.call

      assert generator.warnings.any? { |w| w.include?("ansible.builtin.apt_key") }
      assert generator.warnings.any? { |w| w.include?("ansible.builtin.service") }
      assert rows.any? { |r| r[:module_fqcn] == "ansible.builtin.copy" }
    end

    test "parameter rows carry expected values from raw_doc, not the phrasing response" do
      create_named_module("ansible.builtin.copy", "copy")
      stub_openai_structured_response("questions" => [ "unrelated stubbed question" ])

      rows = new_generator.call
      backup_row = rows.find { |r| r[:stable_id] == "ansible.builtin.copy::param::backup" }

      backup_option = raw_doc_fixture("copy")["doc"]["options"]["backup"]

      assert_equal backup_option["type"], backup_row[:expected_type]
      assert_equal backup_option["default"], backup_row[:expected_default]
    end

    test "deprecation rows carry expected_deprecated/expected_alternative from raw_doc, not the phrasing response" do
      create_named_module("ansible.builtin.apt_key", "apt_key")
      stub_openai_structured_response("questions" => [ "is this even a real question" ])

      rows = new_generator.call
      overview_row = rows.find { |r| r[:stable_id] == "ansible.builtin.apt_key::overview" }

      assert_equal true, overview_row[:expected_deprecated]
      assert_equal "ansible.builtin.deb822_repository", overview_row[:expected_alternative]
    end

    test "a non-deprecated module's overview row expects not-deprecated with no alternative" do
      create_named_module("ansible.builtin.copy", "copy")
      stub_openai_structured_response("questions" => [ "is copy deprecated" ])

      rows = new_generator.call
      overview_row = rows.find { |r| r[:stable_id] == "ansible.builtin.copy::overview" }

      assert_equal false, overview_row[:expected_deprecated]
      assert_nil overview_row[:expected_alternative]
    end

    test "only produces parameter and overview rows, never return-value rows" do
      create_named_module("ansible.builtin.copy", "copy")
      stub_openai_structured_response("questions" => [ "q" ])

      rows = new_generator.call

      assert_equal [ "overview", "parameter" ], rows.map { |r| r[:chunk_type] }.uniq.sort
    end

    test "only generates rows for named modules, even when other modules are ingested" do
      create_named_module("ansible.builtin.copy", "copy")
      AnsibleModule.create!(fqcn: "ansible.builtin.uri", ansible_core_version: "2.21.2", raw_doc: raw_doc_fixture("uri"))
      stub_openai_structured_response("questions" => [ "q" ])

      rows = new_generator.call

      assert rows.all? { |r| Eval::NAMED_MODULES.include?(r[:module_fqcn]) }
      refute rows.any? { |r| r[:module_fqcn] == "ansible.builtin.uri" }
    end
  end
end

require "test_helper"

module Eval
  class CompositionalCheckerTest < ActiveSupport::TestCase
    def create_copy_module
      AnsibleModule.create!(
        fqcn: "ansible.builtin.copy",
        ansible_core_version: "2.21.2",
        raw_doc: {
          "doc" => {
            "options" => {
              "dest" => { "type" => "path", "required" => true },
              "src" => { "type" => "path", "required" => false },
              "mode" => { "type" => "raw", "required" => false }
            }
          }
        }
      )
    end

    test "flags YAML that fails to parse as invalid" do
      result = CompositionalChecker.call("not: [valid, yaml")

      assert_equal false, result[:yaml_valid]
    end

    test "valid YAML with only real module and parameter names has no unknown names" do
      create_copy_module

      yaml = <<~YAML
        ```yaml
        - name: copy a file
          ansible.builtin.copy:
            dest: /etc/motd
            src: /tmp/motd
            mode: '0666'
        ```
      YAML

      result = CompositionalChecker.call(yaml)

      assert_equal true, result[:yaml_valid]
      assert_empty result[:unknown_names]
    end

    test "flags a hallucinated parameter name that doesn't exist on the module" do
      create_copy_module

      yaml = <<~YAML
        ```yaml
        - name: copy a file
          ansible.builtin.copy:
            dest: /etc/motd
            permissions: '0666'
        ```
      YAML

      result = CompositionalChecker.call(yaml)

      assert_includes result[:unknown_names], "ansible.builtin.copy.permissions"
    end

    test "flags a hallucinated module name that doesn't exist in the ingested corpus" do
      create_copy_module

      yaml = <<~YAML
        ```yaml
        - name: do a thing
          ansible.builtin.totally_made_up_module:
            foo: bar
        ```
      YAML

      result = CompositionalChecker.call(yaml)

      assert_includes result[:unknown_names], "ansible.builtin.totally_made_up_module"
    end

    test "flags a missing required parameter" do
      create_copy_module

      yaml = <<~YAML
        ```yaml
        - name: copy a file
          ansible.builtin.copy:
            src: /tmp/motd
        ```
      YAML

      result = CompositionalChecker.call(yaml)

      assert_includes result[:missing_required], "ansible.builtin.copy.dest"
    end

    test "does not flag a required parameter that is present" do
      create_copy_module

      yaml = <<~YAML
        ```yaml
        - name: copy a file
          ansible.builtin.copy:
            dest: /etc/motd
            src: /tmp/motd
        ```
      YAML

      result = CompositionalChecker.call(yaml)

      assert_empty result[:missing_required]
    end
  end
end

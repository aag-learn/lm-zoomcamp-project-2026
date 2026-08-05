require "test_helper"

class GetModuleDetailsTest < ActiveSupport::TestCase
  test "returns the raw_doc for an existing module" do
    raw_doc = { "short_description" => "Copy files to remote locations" }
    AnsibleModule.create!(fqcn: "ansible.builtin.copy", ansible_core_version: "2.21.2", raw_doc: raw_doc)

    result = GetModuleDetails.new.execute(fqcn: "ansible.builtin.copy")

    assert_equal raw_doc, JSON.parse(result)
  end

  test "returns a clear not-found message instead of raising for an unknown fqcn" do
    result = GetModuleDetails.new.execute(fqcn: "ansible.builtin.does_not_exist")

    assert_match(/not found/i, result)
  end
end

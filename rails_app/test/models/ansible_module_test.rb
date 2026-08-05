require "test_helper"

class AnsibleModuleTest < ActiveSupport::TestCase
  test "has many chunks and destroys them when destroyed" do
    ansible_module = AnsibleModule.create!(
      fqcn: "ansible.builtin.copy",
      ansible_core_version: "2.21.2"
    )
    chunk = ansible_module.chunks.create!(
      chunk_type: "overview",
      stable_id: "ansible.builtin.copy::overview",
      content: "Copies files to remote locations.",
      embedding: Array.new(384, 0.0),
      ansible_core_version: "2.21.2"
    )

    assert_equal [ chunk ], ansible_module.chunks

    ansible_module.destroy!

    assert_nil Chunk.find_by(id: chunk.id)
  end
end

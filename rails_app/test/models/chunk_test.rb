require "test_helper"

class ChunkTest < ActiveSupport::TestCase
  setup do
    @ansible_module = AnsibleModule.create!(
      fqcn: "ansible.builtin.copy",
      ansible_core_version: "2.21.2"
    )
  end

  test "belongs to an ansible module" do
    chunk = @ansible_module.chunks.create!(
      chunk_type: "overview",
      stable_id: "ansible.builtin.copy::overview",
      content: "Copies files to remote locations.",
      embedding: Array.new(384, 0.0),
      ansible_core_version: "2.21.2"
    )

    assert_equal @ansible_module, chunk.ansible_module
  end

  test ".search finds a chunk by a keyword in its content, ranked by relevance" do
    copy_chunk = @ansible_module.chunks.create!(
      chunk_type: "overview",
      stable_id: "ansible.builtin.copy::overview",
      content: "The copy module transfers files to remote locations.",
      embedding: Array.new(384, 0.0),
      ansible_core_version: "2.21.2"
    )
    apt_chunk = @ansible_module.chunks.create!(
      chunk_type: "overview",
      stable_id: "ansible.builtin.apt::overview",
      content: "The apt module manages packages on Debian systems.",
      embedding: Array.new(384, 0.0),
      ansible_core_version: "2.21.2"
    )

    results = Chunk.search("copy files")

    assert_includes results, copy_chunk
    assert_not_includes results, apt_chunk
  end

  test "has_neighbors finds the nearest chunk by embedding" do
    near_chunk = @ansible_module.chunks.create!(
      chunk_type: "overview",
      stable_id: "ansible.builtin.copy::overview",
      content: "near",
      embedding: Array.new(384, 1.0),
      ansible_core_version: "2.21.2"
    )
    far_chunk = @ansible_module.chunks.create!(
      chunk_type: "parameter",
      stable_id: "ansible.builtin.copy::param::mode",
      content: "far",
      embedding: Array.new(384, -1.0),
      ansible_core_version: "2.21.2"
    )
    query = @ansible_module.chunks.create!(
      chunk_type: "parameter",
      stable_id: "ansible.builtin.copy::param::query",
      content: "query",
      embedding: Array.new(384, 0.9),
      ansible_core_version: "2.21.2"
    )

    nearest = query.nearest_neighbors(:embedding, distance: "cosine").first

    assert_equal near_chunk, nearest
    assert_not_equal far_chunk, nearest
  end
end

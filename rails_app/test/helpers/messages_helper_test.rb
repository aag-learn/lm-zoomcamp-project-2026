require "test_helper"

class MessagesHelperTest < ActionView::TestCase
  setup do
    chat = Chat.create!
    @message = chat.messages.create!(role: "assistant", content: "hello")
  end

  test "citation_groups returns {} when there's no retrieval_log" do
    assert_equal({}, citation_groups(nil))
  end

  test "citation_groups groups resolved chunks by module fqcn" do
    copy_module = create_module("ansible.builtin.copy")
    create_chunk(ansible_module: copy_module, stable_id: "ansible.builtin.copy::param::mode", content: "mode")
    create_chunk(ansible_module: copy_module, stable_id: "ansible.builtin.copy::param::src", content: "src")

    log = RetrievalLog.create!(
      message: @message,
      retrieval_strategy: "hybrid_rerank",
      retrieved_chunks: [
        { stable_id: "ansible.builtin.copy::param::mode", rrf_score: 0.1, rerank_score: 0.9 },
        { stable_id: "ansible.builtin.copy::param::src", rrf_score: 0.2, rerank_score: 0.8 }
      ]
    )

    groups = citation_groups(log)

    assert_equal [ "mode", "src" ], groups.fetch("ansible.builtin.copy").sort
  end

  test "citation_groups silently omits a stable_id that no longer resolves to any Chunk" do
    copy_module = create_module("ansible.builtin.copy")
    create_chunk(ansible_module: copy_module, stable_id: "ansible.builtin.copy::param::mode", content: "mode")

    log = RetrievalLog.create!(
      message: @message,
      retrieval_strategy: "hybrid_rerank",
      retrieved_chunks: [
        { stable_id: "ansible.builtin.copy::param::mode", rrf_score: 0.1, rerank_score: 0.9 },
        { stable_id: "ansible.builtin.copy::param::removed_in_later_release", rrf_score: 0.05, rerank_score: 0.4 }
      ]
    )

    groups = nil
    assert_nothing_raised { groups = citation_groups(log) }

    assert_equal [ "mode" ], groups.fetch("ansible.builtin.copy")
  end
end

require "test_helper"

class RetrievalLogTest < ActiveSupport::TestCase
  setup do
    chat = Chat.create!
    @message = chat.messages.create!(role: "assistant", content: "hello")
  end

  test "valid with a message and a retrieval_strategy" do
    log = RetrievalLog.new(message: @message, retrieval_strategy: "hybrid_rerank")

    assert log.valid?
  end

  test "invalid without a retrieval_strategy" do
    log = RetrievalLog.new(message: @message)

    assert_not log.valid?
  end

  test "retrieved_chunks defaults to an empty array" do
    log = RetrievalLog.create!(message: @message, retrieval_strategy: "hybrid_rerank")

    assert_equal [], log.retrieved_chunks
  end

  test "stores retrieved_chunks as an array of stable_id/score triples" do
    log = RetrievalLog.create!(
      message: @message,
      retrieval_strategy: "hybrid_rerank",
      retrieved_chunks: [
        { stable_id: "ansible.builtin.copy::param::src", rrf_score: 0.03, rerank_score: 0.91 }
      ]
    )

    reloaded = log.reload.retrieved_chunks.first
    assert_equal "ansible.builtin.copy::param::src", reloaded["stable_id"]
    assert_equal 0.03, reloaded["rrf_score"]
    assert_equal 0.91, reloaded["rerank_score"]
  end

  test "only one retrieval_log per message at the database level" do
    RetrievalLog.create!(message: @message, retrieval_strategy: "hybrid_rerank")

    assert_raises(ActiveRecord::RecordNotUnique) do
      RetrievalLog.create!(message: @message, retrieval_strategy: "hybrid_rerank")
    end
  end
end

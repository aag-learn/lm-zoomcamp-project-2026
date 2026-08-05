require "test_helper"

class MessagesRenderingTest < ActionView::TestCase
  test "rendering a tool-call message produces no visible output" do
    chat = Chat.create!
    tool_call_message = chat.messages.create!(role: "assistant", content: "")
    tool_call_message.tool_calls.create!(
      tool_call_id: "call_1", name: "search_ansible_docs", arguments: { query: "brew install" }
    )

    output = render(tool_call_message)

    assert_predicate output.strip, :empty?
  end

  test "rendering a tool-result message produces no visible output" do
    chat = Chat.create!
    tool_call_message = chat.messages.create!(role: "assistant", content: "")
    tool_call = tool_call_message.tool_calls.create!(
      tool_call_id: "call_1", name: "search_ansible_docs", arguments: { query: "brew install" }
    )
    tool_result_message = chat.messages.create!(
      role: "tool", content: "RAW_TOOL_RESULT_MARKER some retrieved doc content", tool_call_id: tool_call.id
    )

    output = render(tool_result_message)

    assert_predicate output.strip, :empty?
    assert_not_includes output, "RAW_TOOL_RESULT_MARKER"
  end

  test "rendering a system message produces no visible output" do
    chat = Chat.create!
    chat.with_instructions("SYSTEM_INSTRUCTIONS_MARKER always verify against the docs")
    system_message = chat.messages.find_by(role: "system")

    output = render(system_message)

    assert_predicate output.strip, :empty?
    assert_not_includes output, "SYSTEM_INSTRUCTIONS_MARKER"
  end

  test "an assistant message with a RetrievalLog shows a retrieval-details affordance, not an inline Sources line" do
    chat = Chat.create!
    assistant = chat.messages.create!(role: "assistant", content: "answer")
    RetrievalLog.create!(
      message: assistant, retrieval_strategy: "hybrid_rerank", top_module: "ansible.builtin.copy",
      ansible_core_version: "2.21.3", cost: 0.0012, response_time: 1.23,
      retrieved_chunks: [ { stable_id: "ansible.builtin.copy::param::mode", rrf_score: 0.1, rerank_score: 0.9 } ]
    )

    output = render(partial: "messages/assistant", locals: { assistant: assistant })

    assert_includes output, "retrieval-details"
    assert_not_includes output, "Sources:"
  end

  test "an assistant message with no RetrievalLog shows no retrieval-details affordance" do
    chat = Chat.create!
    assistant = chat.messages.create!(role: "assistant", content: "hi there")

    output = render(partial: "messages/assistant", locals: { assistant: assistant })

    assert_not_includes output, "retrieval-details"
    assert_not_includes output, "Sources:"
  end

  test "the retrieval-details dialog shows the log's data as-is, including for a log with only low/negative scores" do
    chat = Chat.create!
    assistant = chat.messages.create!(role: "assistant", content: "hi there")
    RetrievalLog.create!(
      message: assistant, retrieval_strategy: "hybrid_rerank", top_module: "ansible.builtin.ping",
      ansible_core_version: "2.21.3", cost: 0.0004, response_time: 0.87,
      retrieved_chunks: [
        { stable_id: "ansible.builtin.ping::overview", rrf_score: 0.02, rerank_score: -8.86 }
      ]
    )

    output = render(partial: "messages/assistant", locals: { assistant: assistant })

    assert_includes output, "ansible.builtin.ping::overview"
    assert_includes output, "-8.86"
    assert_includes output, "ansible.builtin.ping"
    assert_includes output, "2.21.3"
    assert_includes output, "0.87"
  end
end

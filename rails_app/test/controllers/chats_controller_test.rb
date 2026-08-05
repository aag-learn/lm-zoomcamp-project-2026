require "test_helper"

class ChatsControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as(users(:one)) }

  test "reloading a chat's page returns all previously persisted messages" do
    chat = Chat.create!
    chat.messages.create!(role: "user", content: "what does the copy module do")
    chat.messages.create!(role: "assistant", content: "it copies files to remote hosts")

    get chat_path(chat)

    assert_response :success
    assert_includes response.body, "what does the copy module do"
    assert_includes response.body, "it copies files to remote hosts"
  end

  test "a tool-using reply's transcript shows only the user message and the final answer" do
    chat = Chat.create!
    chat.messages.create!(role: "user", content: "how can I install a brew package using ansible")

    tool_call_message = chat.messages.create!(role: "assistant", content: "")
    tool_call = tool_call_message.tool_calls.create!(
      tool_call_id: "call_1", name: "search_ansible_docs", arguments: { query: "brew install" }
    )
    chat.messages.create!(
      role: "tool", content: "RAW_TOOL_RESULT_MARKER some retrieved doc content", tool_call_id: tool_call.id
    )
    chat.messages.create!(role: "assistant", content: "FINAL_ANSWER_MARKER use the homebrew module")

    get chat_path(chat)

    assert_response :success
    assert_includes response.body, "how can I install a brew package using ansible"
    assert_includes response.body, "FINAL_ANSWER_MARKER use the homebrew module"
    assert_not_includes response.body, "RAW_TOOL_RESULT_MARKER"
    assert_not_includes response.body, "search_ansible_docs"
  end
end

require "test_helper"

class ChatsControllerTest < ActionDispatch::IntegrationTest
  test "reloading a chat's page returns all previously persisted messages" do
    chat = Chat.create!
    chat.messages.create!(role: "user", content: "what does the copy module do")
    chat.messages.create!(role: "assistant", content: "it copies files to remote hosts")

    get chat_path(chat)

    assert_response :success
    assert_includes response.body, "what does the copy module do"
    assert_includes response.body, "it copies files to remote hosts"
  end
end

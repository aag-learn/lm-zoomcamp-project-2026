require "test_helper"

class ChatResponseJobTest < ActiveSupport::TestCase
  def openai_sse_body(reply)
    chunk = { choices: [ { index: 0, delta: { role: "assistant", content: reply }, finish_reason: nil } ] }.to_json
    done = { choices: [ { index: 0, delta: {}, finish_reason: "stop" } ],
             usage: { prompt_tokens: 10, completion_tokens: 2, total_tokens: 12 } }.to_json

    "data: #{chunk}\n\ndata: #{done}\n\ndata: [DONE]\n\n"
  end

  def stub_openai_chat(reply:)
    stub_request(:post, "https://api.openai.com/v1/chat/completions")
      .to_return(status: 200, body: openai_sse_body(reply), headers: { "Content-Type" => "text/event-stream" })
  end

  def openai_multi_chunk_sse_body(*pieces)
    deltas = pieces.map do |piece|
      "data: #{{ choices: [ { index: 0, delta: { content: piece }, finish_reason: nil } ] }.to_json}"
    end
    done = { choices: [ { index: 0, delta: {}, finish_reason: "stop" } ],
             usage: { prompt_tokens: 10, completion_tokens: 2, total_tokens: 12 } }.to_json

    "#{deltas.join("\n\n")}\n\ndata: #{done}\n\ndata: [DONE]\n\n"
  end

  test "a second message within an existing chat stays in that chat, not a new one" do
    chat = Chat.create!

    stub_openai_chat(reply: "first reply")
    ChatResponseJob.perform_now(chat.id, "first question")

    stub_openai_chat(reply: "second reply")
    assert_no_difference("Chat.count") do
      ChatResponseJob.perform_now(chat.id, "second question")
    end

    assert_equal chat.id, Message.last.chat_id
    assert_equal 4, chat.messages.count # 2 user + 2 assistant
  end

  test "a follow-up message's request includes prior messages as context" do
    chat = Chat.create!
    captured_bodies = []

    stub_request(:post, "https://api.openai.com/v1/chat/completions").to_return do |request|
      captured_bodies << JSON.parse(request.body)
      { status: 200, body: openai_sse_body("reply ##{captured_bodies.size}"),
        headers: { "Content-Type" => "text/event-stream" } }
    end

    ChatResponseJob.perform_now(chat.id, "what does the copy module do")
    ChatResponseJob.perform_now(chat.id, "what about its mode parameter")

    first_request_messages, second_request_messages = captured_bodies.map { |b| b["messages"] }

    assert_operator second_request_messages.size, :>, first_request_messages.size
    assert second_request_messages.any? { |m| m["content"].to_s.include?("what does the copy module do") }
  end

  test "reply content accumulates across multiple streamed chunks, not just the final one" do
    chat = Chat.create!

    stub_request(:post, "https://api.openai.com/v1/chat/completions")
      .to_return(status: 200, body: openai_multi_chunk_sse_body("Hello", ", ", "world!"),
                 headers: { "Content-Type" => "text/event-stream" })

    ChatResponseJob.perform_now(chat.id, "hi")

    assert_equal "Hello, world!", Message.last.content
  end
end

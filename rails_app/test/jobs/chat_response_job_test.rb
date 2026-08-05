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

  def openai_tool_call_sse_body(tool_name:, arguments:, call_id: "call_1", prompt_tokens: 50, completion_tokens: 20)
    start = { choices: [ { index: 0,
                            delta: { role: "assistant",
                                     tool_calls: [ { index: 0, id: call_id, type: "function",
                                                     function: { name: tool_name, arguments: "" } } ] },
                            finish_reason: nil } ] }.to_json
    fragment = { choices: [ { index: 0,
                               delta: { tool_calls: [ { index: 0, function: { arguments: arguments } } ] },
                               finish_reason: nil } ] }.to_json
    done = { choices: [ { index: 0, delta: {}, finish_reason: "tool_calls" } ],
             usage: { prompt_tokens: prompt_tokens, completion_tokens: completion_tokens,
                      total_tokens: prompt_tokens + completion_tokens } }.to_json

    "data: #{start}\n\ndata: #{fragment}\n\ndata: #{done}\n\ndata: [DONE]\n\n"
  end

  def stub_search_ansible_docs_tool_call(query:)
    stub_request(:post, "https://api.openai.com/v1/chat/completions")
      .to_return(
        status: 200,
        body: openai_tool_call_sse_body(tool_name: "search_ansible_docs", arguments: { query: query }.to_json),
        headers: { "Content-Type" => "text/event-stream" }
      )
      .to_return(status: 200, body: openai_sse_body("here's what I found"),
                 headers: { "Content-Type" => "text/event-stream" })
  end

  def stub_embed_and_rerank(query:)
    stub_request(:post, "http://embedder:8000/embed")
      .with(body: { texts: [ query ] }.to_json)
      .to_return(
        status: 200,
        body: { embeddings: [ captured_embedding_for("query:#{query}") ] }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    top_content = captured_embeddings.fetch("ansible.builtin.copy::param::src").fetch("text")

    stub_request(:post, "http://embedder:8000/rerank").to_return do |request|
      body = JSON.parse(request.body)
      scores = body["candidates"].map { |c| c == top_content ? 0.9 : 0.1 }
      { status: 200, body: { scores: scores }.to_json, headers: { "Content-Type" => "application/json" } }
    end
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
    assert_equal 5, chat.messages.count # 1 system (grounding instructions) + 2 user + 2 assistant
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

  test "a reply that calls search_ansible_docs gets a RetrievalLog" do
    query = "copy files to a remote host"

    copy_module = create_module("ansible.builtin.copy")
    uri_module = create_module("ansible.builtin.uri")
    create_chunk(
      ansible_module: copy_module,
      stable_id: "ansible.builtin.copy::param::src",
      content: captured_embeddings.fetch("ansible.builtin.copy::param::src").fetch("text"),
      embedding: captured_embedding_for("ansible.builtin.copy::param::src")
    )
    create_chunk(
      ansible_module: uri_module,
      stable_id: "ansible.builtin.uri::param::dest",
      content: captured_embeddings.fetch("ansible.builtin.uri::param::dest").fetch("text"),
      embedding: captured_embedding_for("ansible.builtin.uri::param::dest")
    )

    stub_search_ansible_docs_tool_call(query: query)
    stub_embed_and_rerank(query: query)

    chat = Chat.create!
    assert_difference("RetrievalLog.count", 1) do
      ChatResponseJob.perform_now(chat.id, query)
    end

    log = RetrievalLog.last
    assert_equal Message.last.id, log.message_id
    assert_equal "hybrid_rerank", log.retrieval_strategy
    assert_equal "2.21.2", log.ansible_core_version
    assert_equal "ansible.builtin.copy", log.top_module

    stable_ids = log.retrieved_chunks.map { |c| c["stable_id"] }
    assert_includes stable_ids, "ansible.builtin.copy::param::src"
    assert_includes stable_ids, "ansible.builtin.uri::param::dest"
    log.retrieved_chunks.each do |chunk|
      assert chunk["rrf_score"].is_a?(Numeric)
      assert chunk["rerank_score"].is_a?(Numeric)
    end

    assert_not_nil log.input_tokens
    assert_not_nil log.output_tokens
    assert_not_nil log.response_time
  end

  test "the first completion request forces the search_ansible_docs tool" do
    chat = Chat.create!
    captured_bodies = []

    stub_request(:post, "https://api.openai.com/v1/chat/completions").to_return do |request|
      captured_bodies << JSON.parse(request.body)
      { status: 200, body: openai_sse_body("reply"), headers: { "Content-Type" => "text/event-stream" } }
    end

    ChatResponseJob.perform_now(chat.id, "hi")

    assert_equal(
      { "type" => "function", "function" => { "name" => "search_ansible_docs" } },
      captured_bodies.first["tool_choice"]
    )
  end

  test "every request includes the grounding system instructions, exactly once" do
    chat = Chat.create!
    captured_bodies = []

    stub_request(:post, "https://api.openai.com/v1/chat/completions").to_return do |request|
      captured_bodies << JSON.parse(request.body)
      { status: 200, body: openai_sse_body("reply ##{captured_bodies.size}"),
        headers: { "Content-Type" => "text/event-stream" } }
    end

    ChatResponseJob.perform_now(chat.id, "first question")
    ChatResponseJob.perform_now(chat.id, "second question")

    # gpt-5-mini goes through RubyLLM's OpenAI provider with the default
    # `openai_use_system_role: false`, which sends role "developer" instead
    # of "system" on the wire (see providers/openai/chat.rb#format_role) --
    # the persisted Message row is still role: :system either way.
    first_system_messages, second_system_messages = captured_bodies.map do |body|
      body["messages"].select { |m| m["role"] == "developer" }
    end

    assert_equal 1, first_system_messages.size
    assert_equal 1, second_system_messages.size
    assert_equal ChatResponseJob::SYSTEM_INSTRUCTIONS, second_system_messages.first["content"]
  end

  test "a reply where the search tool finds nothing relevant still gets a RetrievalLog row" do
    query = "hi there"
    stub_search_ansible_docs_tool_call(query: query)

    # No chunks exist in the test DB for this test (no create_chunk calls), so
    # HybridSearch returns no candidates and SearchAnsibleDocs never reaches
    # RerankerClient -- only /embed (for the query vector) needs stubbing.
    stub_request(:post, "http://embedder:8000/embed")
      .with(body: { texts: [ query ] }.to_json)
      .to_return(status: 200, body: { embeddings: [ Array.new(384, 0.0) ] }.to_json,
                 headers: { "Content-Type" => "application/json" })

    chat = Chat.create!
    assert_difference("RetrievalLog.count", 1) do
      ChatResponseJob.perform_now(chat.id, query)
    end

    log = RetrievalLog.last
    assert_equal [], log.retrieved_chunks
    assert_nil log.top_module
    assert_nil log.ansible_core_version
    assert_not_nil log.response_time
  end
end

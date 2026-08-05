require "test_helper"

module Eval
  class LlmEvaluatorTest < ActiveSupport::TestCase
    # Eval::LlmEvaluator#ask_with_tools calls .ask with no block, so RubyLLM
    # sends stream: false and expects a single non-streaming JSON response
    # (unlike ChatResponseJob's streaming .ask, which needs an SSE body).
    def openai_non_streaming_body(reply)
      {
        choices: [ { index: 0, message: { role: "assistant", content: reply }, finish_reason: "stop" } ],
        usage: { prompt_tokens: 10, completion_tokens: 2, total_tokens: 12 }
      }.to_json
    end

    test "ask_with_tools forces the search_ansible_docs tool on the RAG-condition request" do
      captured_body = nil
      stub_request(:post, "https://api.openai.com/v1/chat/completions").to_return do |request|
        captured_body = JSON.parse(request.body)
        { status: 200, body: openai_non_streaming_body("an answer"),
          headers: { "Content-Type" => "application/json" } }
      end

      evaluator = Eval::LlmEvaluator.new([], nil)
      evaluator.send(:ask_with_tools, "what does the mode parameter of the copy module default to?")

      assert_equal(
        { "type" => "function", "function" => { "name" => "search_ansible_docs" } },
        captured_body["tool_choice"]
      )
    end
  end
end

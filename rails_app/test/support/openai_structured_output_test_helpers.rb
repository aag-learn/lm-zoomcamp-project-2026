module OpenaiStructuredOutputTestHelpers
  # A plain (non-streaming) OpenAI chat-completions response, as produced when
  # `RubyLLM::Chat#ask` is called without a block — used for every structured-output
  # call in the eval pipeline (question phrasing, judges), none of which stream.
  def stub_openai_structured_response(content)
    stub_request(:post, "https://api.openai.com/v1/chat/completions").to_return(
      status: 200,
      body: {
        choices: [ { message: { role: "assistant", content: content.to_json } } ],
        usage: { prompt_tokens: 10, completion_tokens: 5, total_tokens: 15 },
        model: "gpt-5-mini"
      }.to_json,
      headers: { "Content-Type" => "application/json" }
    )
  end

  # Same shape, but returns a different stubbed body on each successive call —
  # for tests that need to distinguish e.g. a RAG vs. no-RAG completion.
  def stub_openai_structured_responses(*contents)
    stub = stub_request(:post, "https://api.openai.com/v1/chat/completions")
    contents.each do |content|
      stub = stub.to_return(
        status: 200,
        body: {
          choices: [ { message: { role: "assistant", content: content.to_json } } ],
          usage: { prompt_tokens: 10, completion_tokens: 5, total_tokens: 15 },
          model: "gpt-5-mini"
        }.to_json,
        headers: { "Content-Type" => "application/json" }
      )
    end
  end
end

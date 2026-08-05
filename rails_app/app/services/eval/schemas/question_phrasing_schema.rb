require "ruby_llm/schema"

module Eval
  module Schemas
    # Structured output for ground-truth question phrasing only — the LLM's
    # sole job is wording; expected_* values always come from the app's own
    # ingested doc data (Eval::GroundTruthGenerator), never from this response.
    class QuestionPhrasingSchema < RubyLLM::Schema
      array :questions, description: "Distinct natural-language question phrasings" do
        string
      end
    end
  end
end

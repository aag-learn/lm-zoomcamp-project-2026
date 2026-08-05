require "ruby_llm/schema"

module Eval
  module Schemas
    class RelevanceSchema < RubyLLM::Schema
      string :verdict, enum: %w[RELEVANT NOT_RELEVANT]
    end
  end
end

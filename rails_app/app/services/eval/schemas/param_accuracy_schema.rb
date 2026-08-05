require "ruby_llm/schema"

module Eval
  module Schemas
    class ParamAccuracySchema < RubyLLM::Schema
      string :verdict, enum: %w[CORRECT INCORRECT NOT_STATED]
    end
  end
end

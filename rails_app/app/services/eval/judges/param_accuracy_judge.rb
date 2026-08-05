module Eval
  module Judges
    # Judges a generated answer against a ground-truth row's expected values —
    # parameter rows are checked against expected_type/default/choices,
    # overview (deprecation) rows against expected_deprecated/expected_alternative.
    # Kept as one judge (not two) since both share the same CORRECT/INCORRECT/
    # NOT_STATED verdict shape — see design.md.
    class ParamAccuracyJudge
      def self.call(row:, answer:)
        prompt = row[:chunk_type] == "overview" ? deprecation_prompt(row, answer) : parameter_prompt(row, answer)

        RubyLLM.chat.with_schema(Eval::Schemas::ParamAccuracySchema).ask(prompt).content["verdict"]
      end

      def self.parameter_prompt(row, answer)
        <<~PROMPT
          Question: #{row[:question]}
          Answer: #{answer}

          The real, correct values are:
          - type: #{row[:expected_type]}
          - default: #{row[:expected_default].inspect}
          - choices: #{Array(row[:expected_choices]).join(', ')}

          Does the answer correctly state these values? Respond CORRECT if it
          matches the real values, INCORRECT if it states a wrong value, or
          NOT_STATED if the answer doesn't address the value at all.
        PROMPT
      end
      private_class_method :parameter_prompt

      def self.deprecation_prompt(row, answer)
        <<~PROMPT
          Question: #{row[:question]}
          Answer: #{answer}

          The real, correct facts are:
          - deprecated: #{row[:expected_deprecated]}
          - alternative module (if deprecated): #{row[:expected_alternative]}

          Does the answer correctly state whether the module is deprecated
          (and its replacement, if applicable)? Respond CORRECT if it matches
          the real facts, INCORRECT if it states the wrong deprecation status
          or alternative, or NOT_STATED if the answer doesn't address it.
        PROMPT
      end
      private_class_method :deprecation_prompt
    end
  end
end

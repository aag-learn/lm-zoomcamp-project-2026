require "test_helper"

module Eval
  module Judges
    class ParamAccuracyJudgeTest < ActiveSupport::TestCase
      test "judges a parameter question's answer against expected_type/default/choices" do
        stub_openai_structured_response("verdict" => "CORRECT")

        row = {
          chunk_type: "parameter",
          question: "What does the mode parameter default to?",
          expected_type: "raw",
          expected_default: nil,
          expected_choices: []
        }

        verdict = ParamAccuracyJudge.call(row: row, answer: "It has no default value.")

        assert_equal "CORRECT", verdict
      end

      test "judges a deprecation question's answer against expected_deprecated/expected_alternative" do
        stub_openai_structured_response("verdict" => "INCORRECT")

        row = {
          chunk_type: "overview",
          question: "Is apt_key deprecated?",
          expected_deprecated: true,
          expected_alternative: "ansible.builtin.deb822_repository"
        }

        verdict = ParamAccuracyJudge.call(row: row, answer: "No, it is not deprecated.")

        assert_equal "INCORRECT", verdict
      end

      test "returns NOT_STATED verdicts from the judge unchanged" do
        stub_openai_structured_response("verdict" => "NOT_STATED")

        row = { chunk_type: "parameter", question: "q", expected_type: "str", expected_default: nil, expected_choices: [] }

        verdict = ParamAccuracyJudge.call(row: row, answer: "I'm not sure.")

        assert_equal "NOT_STATED", verdict
      end
    end
  end
end

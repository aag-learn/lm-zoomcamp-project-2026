require "test_helper"

module Eval
  module Judges
    class RelevanceJudgeTest < ActiveSupport::TestCase
      test "judges whether an answer is relevant to the question" do
        stub_openai_structured_response("verdict" => "RELEVANT")

        verdict = RelevanceJudge.call(question: "What does copy's mode parameter do?", answer: "It sets file permissions.")

        assert_equal "RELEVANT", verdict
      end

      test "reports a NOT_RELEVANT verdict from the judge unchanged" do
        stub_openai_structured_response("verdict" => "NOT_RELEVANT")

        verdict = RelevanceJudge.call(question: "What does copy's mode parameter do?", answer: "The sky is blue.")

        assert_equal "NOT_RELEVANT", verdict
      end
    end
  end
end

require "test_helper"

class EvaluationsControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as(users(:one)) }

  test "shows a no-results-yet state when nothing has been generated" do
    Eval::GroundTruth.stub(:load, []) do
      Eval::EvalResults.stub(:load, nil) do
        get evaluation_path
      end
    end

    assert_response :success
    assert_match(/no.*results/i, response.body)
  end

  test "shows the pinned version and eval sections when results are present" do
    results = {
      "generated_at" => "2026-08-20T00:00:00Z",
      "ansible_core_version" => "2.21.2",
      "retrieval" => { "hybrid_rerank" => { "hit_rate" => 0.9, "mrr" => 0.75 } },
      "llm" => { "rag_accuracy" => 0.8, "no_rag_accuracy" => 0.4, "question_count" => 20 },
      "compositional" => {
        "pass_rate" => 0.5,
        "results" => [
          { "module_fqcn" => "ansible.builtin.copy", "yaml_valid" => true, "unknown_names" => [], "missing_required" => [] }
        ]
      }
    }

    Eval::GroundTruth.stub(:load, [ { module_fqcn: "ansible.builtin.copy" } ]) do
      Eval::EvalResults.stub(:load, results) do
        get evaluation_path
      end
    end

    assert_response :success
    assert_match "2.21.2", response.body
    assert_match "hybrid_rerank", response.body
    assert_match "ansible.builtin.copy", response.body
  end
end

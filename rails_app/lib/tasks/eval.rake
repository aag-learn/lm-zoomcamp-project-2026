# These tasks run long enough (the LLM/retrieval evals make hundreds to
# thousands of real HTTP calls) that progress logging is only useful if it's
# actually visible while running, not just after the process exits — Ruby
# fully buffers STDOUT when it isn't a TTY (e.g. piped through `podman exec`),
# so without this, Rails.logger output sits in an in-process buffer and never
# reaches the pipe until it fills or the task finishes.
$stdout.sync = true

namespace :eval do
  desc "Generate ground truth (data/ground_truth.csv), pinned to the currently ingested ansible-core version"
  task ground_truth: :environment do
    generator = Eval::GroundTruthGenerator.new
    rows = generator.call

    generator.warnings.each { |warning| warn "WARNING: #{warning}" }
    puts "Wrote #{rows.size} ground-truth rows to #{Eval::GroundTruth::DEFAULT_PATH}"
  end

  desc "Score keyword/vector/hybrid/hybrid+rerank retrieval against the pinned ground truth"
  task retrieval: :environment do
    results = Eval::RetrievalEvaluator.call

    results.each do |strategy, scores|
      puts "#{strategy}: hit_rate=#{scores[:hit_rate].round(3)} mrr=#{scores[:mrr].round(3)}"
    end
  end

  desc "Judge RAG vs. no-RAG answers against the pinned ground truth (EVAL_SAMPLE_SIZE=N to limit)"
  task llm: :environment do
    result = Eval::LlmEvaluator.call(limit: ENV["EVAL_SAMPLE_SIZE"])

    puts "RAG accuracy:    #{(result[:rag_accuracy] * 100).round(1)}%"
    puts "No-RAG accuracy: #{(result[:no_rag_accuracy] * 100).round(1)}%"
  end

  desc "Check generated task YAML for the 6 named modules against the ingested corpus"
  task compositional: :environment do
    results = Eval::CompositionalEvaluator.call

    results.each do |result|
      status = result[:yaml_valid] && result[:unknown_names].empty? && result[:missing_required].empty? ? "PASS" : "FAIL"
      puts "#{status} #{result[:module_fqcn]}: valid=#{result[:yaml_valid]} " \
           "unknown=#{result[:unknown_names]} missing_required=#{result[:missing_required]}"
    end
  end

  desc "Run the full eval pipeline (ground truth -> retrieval -> LLM -> compositional), writing data/eval_results.json " \
       "(SKIP_GROUND_TRUTH=1 to reuse the existing data/ground_truth.csv instead of regenerating it)"
  task all: :environment do
    reuse_existing = ENV["SKIP_GROUND_TRUTH"].present? && File.exist?(Eval::GroundTruth::DEFAULT_PATH)

    if reuse_existing
      Rails.logger.info("[eval:all] SKIP_GROUND_TRUTH set — reusing #{Eval::GroundTruth::DEFAULT_PATH}")
      rows = Eval::GroundTruth.load
    else
      generator = Eval::GroundTruthGenerator.new
      rows = generator.call
      generator.warnings.each { |warning| warn "WARNING: #{warning}" }
    end

    retrieval = Eval::RetrievalEvaluator.call(ground_truth: rows)
    llm = Eval::LlmEvaluator.call(ground_truth: rows, limit: ENV["EVAL_SAMPLE_SIZE"])
    compositional = Eval::CompositionalEvaluator.call

    Eval::EvalResults.write(
      retrieval: retrieval,
      llm: llm,
      compositional: compositional,
      ansible_core_version: rows.first&.dig(:ansible_core_version)
    )

    puts "Wrote eval results to #{Eval::EvalResults::DEFAULT_PATH}"
  end
end

require "json"

module Eval
  # Reads and writes data/eval_results.json — the compact aggregate written by
  # `eval:all`: hit_rate/MRR per retrieval strategy, RAG-vs-no-RAG accuracy,
  # and compositional-eval pass rate, plus the ansible_core_version/timestamp
  # the run is pinned to. Deliberately excludes full per-question transcripts
  # to keep this a small, page-renderable artifact — see design.md.
  module EvalResults
    DEFAULT_PATH = Rails.root.join("data/eval_results.json")

    def self.write(retrieval:, llm:, compositional:, ansible_core_version:, path: DEFAULT_PATH)
      payload = {
        generated_at: Time.current.iso8601,
        ansible_core_version: ansible_core_version,
        retrieval: retrieval,
        llm: {
          rag_accuracy: llm[:rag_accuracy],
          no_rag_accuracy: llm[:no_rag_accuracy],
          question_count: llm[:results].size
        },
        compositional: {
          pass_rate: compositional_pass_rate(compositional),
          results: compositional.map { |r| r.slice(:module_fqcn, :yaml_valid, :unknown_names, :missing_required) }
        }
      }

      File.write(path, JSON.pretty_generate(payload))
      payload
    end

    def self.load(path: DEFAULT_PATH)
      return nil unless File.exist?(path)

      JSON.parse(File.read(path))
    end

    def self.compositional_pass_rate(compositional)
      return 0.0 if compositional.empty?

      passing = compositional.count { |r| r[:yaml_valid] && r[:unknown_names].empty? && r[:missing_required].empty? }
      passing.to_f / compositional.size
    end
  end
end

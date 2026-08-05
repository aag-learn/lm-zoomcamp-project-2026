require "concurrent"

module Eval
  # Runs every ground-truth question through the live app's own tool-calling
  # setup (RAG condition) and through a plain chat with no tools (no-RAG
  # condition), judging both for relevance and parameter/deprecation accuracy —
  # the primary RAG-vs-no-RAG accuracy comparison this eval exists to produce.
  class LlmEvaluator
    # Rows are fully independent (each judges its own question), so they run
    # BATCH_SIZE at a time in their own threads rather than one at a time —
    # at 450 questions x 6 calls each, sequential execution is the dominant
    # cost of the whole eval pipeline. Sized to the default ActiveRecord pool
    # (`database.yml`'s `RAILS_MAX_THREADS`-or-5) rather than higher, since a
    # RAG-condition row can indirectly hit the DB via SearchAnsibleDocs — going
    # higher would need a connection-pool bump to avoid checkout timeouts.
    BATCH_SIZE = 5

    def self.call(ground_truth: GroundTruth.load, limit: nil)
      new(ground_truth, limit).call
    end

    def initialize(ground_truth, limit)
      @ground_truth = limit ? StratifiedSample.take(ground_truth, limit.to_i, by: :module_fqcn) : ground_truth
    end

    def call
      total = @ground_truth.size
      completed = Concurrent::AtomicFixnum.new(0)

      results = @ground_truth.each_slice(BATCH_SIZE).flat_map do |batch|
        batch.map { |row| Thread.new { evaluate_and_log(row, completed, total) } }.map(&:value)
      end

      {
        results: results,
        rag_accuracy: accuracy(results, :rag_param_verdict),
        no_rag_accuracy: accuracy(results, :no_rag_param_verdict)
      }
    end

    private

    # `with_connection` returns the checked-out AR connection to the pool as
    # soon as this thread's work is done, rather than leaking it until Rails'
    # reaper eventually notices — required for ad-hoc Thread.new use, unlike
    # thread pools Rails manages itself (e.g. Puma's, ActiveJob's).
    def evaluate_and_log(row, completed, total)
      result = ActiveRecord::Base.connection_pool.with_connection { evaluate_row(row) }
      Rails.logger.info("[Eval::LlmEvaluator] #{completed.increment}/#{total} #{row[:stable_id]}")
      result
    end

    def evaluate_row(row)
      rag_answer = ask_with_tools(row[:question])
      no_rag_answer = ask_without_tools(row[:question])

      {
        stable_id: row[:stable_id],
        question: row[:question],
        rag_answer: rag_answer,
        no_rag_answer: no_rag_answer,
        rag_relevance: Judges::RelevanceJudge.call(question: row[:question], answer: rag_answer),
        rag_param_verdict: Judges::ParamAccuracyJudge.call(row: row, answer: rag_answer),
        no_rag_relevance: Judges::RelevanceJudge.call(question: row[:question], answer: no_rag_answer),
        no_rag_param_verdict: Judges::ParamAccuracyJudge.call(row: row, answer: no_rag_answer)
      }
    end

    def ask_with_tools(question)
      RubyLLM.chat.with_tools(SearchAnsibleDocs.new, GetModuleDetails).ask(question).content
    end

    def ask_without_tools(question)
      RubyLLM.chat.ask(question).content
    end

    def accuracy(results, key)
      return 0.0 if results.empty?

      results.count { |result| result[key] == "CORRECT" }.to_f / results.size
    end
  end
end

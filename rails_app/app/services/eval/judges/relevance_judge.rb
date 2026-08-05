module Eval
  module Judges
    class RelevanceJudge
      def self.call(question:, answer:)
        prompt = <<~PROMPT
          Question: #{question}
          Answer: #{answer}

          Does the answer address the question, regardless of whether it is
          factually correct? Respond RELEVANT or NOT_RELEVANT.
        PROMPT

        RubyLLM.chat.with_schema(Eval::Schemas::RelevanceSchema).ask(prompt).content["verdict"]
      end
    end
  end
end

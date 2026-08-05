module Eval
  # Generates ground-truth questions from the 6 modules in Eval::NAMED_MODULES.
  # Expected values (type/default/choices/deprecated/alternative) are read
  # directly from AnsibleModule#raw_doc — the LLM is only asked to phrase
  # question text, never to supply the checkable values themselves.
  class GroundTruthGenerator
    attr_reader :warnings

    def initialize(path: GroundTruth::DEFAULT_PATH)
      @path = path
      @warnings = []
    end

    def call
      generated_at = Time.current.iso8601
      modules = named_modules
      rows = modules.each_with_index.flat_map do |ansible_module, index|
        Rails.logger.info("[Eval::GroundTruthGenerator] #{index + 1}/#{modules.size} #{ansible_module.fqcn}")
        parameter_rows(ansible_module, generated_at) + overview_rows(ansible_module, generated_at)
      end

      GroundTruth.write(rows, path: @path)
      rows
    end

    private

    def named_modules
      found = AnsibleModule.where(fqcn: Eval::NAMED_MODULES).index_by(&:fqcn)

      Eval::NAMED_MODULES.each do |fqcn|
        next if found.key?(fqcn)

        @warnings << "Named module #{fqcn} is missing from the ingested corpus — skipping it. " \
                     "If it has been removed upstream, update Eval::NAMED_MODULES with a replacement " \
                     "and record the swap in docs/evaluation-results.md."
      end

      found.values
    end

    def parameter_rows(ansible_module, generated_at)
      options = ansible_module.raw_doc.dig("doc", "options") || {}

      options.each_with_index.flat_map do |(name, option), index|
        Rails.logger.info("[Eval::GroundTruthGenerator]   param #{index + 1}/#{options.size} #{ansible_module.fqcn}::#{name}")

        phrase_parameter_questions(ansible_module.fqcn, name, option).map do |question|
          {
            id: SecureRandom.uuid,
            module_fqcn: ansible_module.fqcn,
            chunk_type: "parameter",
            stable_id: "#{ansible_module.fqcn}::param::#{name}",
            question: question,
            expected_type: option["type"],
            expected_default: option["default"],
            expected_choices: Array(option["choices"]),
            expected_deprecated: nil,
            expected_alternative: nil,
            ansible_core_version: ansible_module.ansible_core_version,
            generated_at: generated_at
          }
        end
      end
    end

    def overview_rows(ansible_module, generated_at)
      deprecated = ansible_module.raw_doc.dig("doc", "deprecated")

      [ {
        id: SecureRandom.uuid,
        module_fqcn: ansible_module.fqcn,
        chunk_type: "overview",
        stable_id: "#{ansible_module.fqcn}::overview",
        question: phrase_deprecation_question(ansible_module.fqcn),
        expected_type: nil,
        expected_default: nil,
        expected_choices: [],
        expected_deprecated: deprecated.present?,
        expected_alternative: deprecated && deprecated["alternative"],
        ansible_core_version: ansible_module.ansible_core_version,
        generated_at: generated_at
      } ]
    end

    def phrase_parameter_questions(fqcn, name, option)
      prompt = <<~PROMPT
        Write 2 to 3 distinct natural-language questions a user might ask about
        the `#{name}` parameter of the Ansible module `#{fqcn}`, given this
        parameter documentation:

        #{option.to_json}

        Only ask about its type, default value, or valid choices — do not
        state the answer in the question itself.
      PROMPT

      RubyLLM.chat.with_schema(Eval::Schemas::QuestionPhrasingSchema).ask(prompt).content["questions"]
    end

    def phrase_deprecation_question(fqcn)
      prompt = "Write exactly 1 natural-language question asking whether the Ansible " \
               "module `#{fqcn}` is deprecated and, if so, what to use instead. Do not " \
               "state the answer in the question itself."

      RubyLLM.chat.with_schema(Eval::Schemas::QuestionPhrasingSchema).ask(prompt).content["questions"].first
    end
  end
end

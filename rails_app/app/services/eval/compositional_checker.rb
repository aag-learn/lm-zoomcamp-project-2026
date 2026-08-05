require "yaml"

module Eval
  # Checks a generated task-YAML answer against the ingested corpus. All three
  # checks are deterministic lookups, not judgment calls — see design.md
  # ("Compositional eval needs no LLM judge at all").
  class CompositionalChecker
    NON_MODULE_KEYS = %w[
      name become become_user when register tags vars vars_files
      loop with_items notify listen block rescue always
      import_tasks include_tasks ignore_errors changed_when failed_when
      delegate_to run_once no_log environment args
    ].freeze

    def self.call(text)
      new(text).call
    end

    def initialize(text)
      @text = text
    end

    def call
      parsed = parse_yaml
      return { yaml_valid: false, unknown_names: [], missing_required: [] } unless parsed

      unknown_names = []
      missing_required = []

      each_module_invocation(parsed) do |fqcn, ansible_module, params|
        if ansible_module.nil?
          unknown_names << fqcn
          next
        end

        options = ansible_module.raw_doc.dig("doc", "options") || {}
        param_names = params.keys.map(&:to_s)

        param_names.each { |name| unknown_names << "#{fqcn}.#{name}" unless options.key?(name) }

        required = options.select { |_name, option| option["required"] }.keys
        missing_required.concat((required - param_names).map { |name| "#{fqcn}.#{name}" })
      end

      { yaml_valid: true, unknown_names: unknown_names, missing_required: missing_required }
    end

    private

    def parse_yaml
      block = extract_fenced_block(@text) || @text
      YAML.safe_load(block, permitted_classes: [ Date, Time ], aliases: true)
    rescue Psych::SyntaxError
      nil
    end

    def extract_fenced_block(text)
      text[/```(?:yaml|yml)?\s*\n(.*?)```/m, 1]
    end

    def each_module_invocation(parsed)
      tasks = parsed.is_a?(Array) ? parsed : [ parsed ]

      tasks.each do |task|
        next unless task.is_a?(Hash)

        task.each do |key, value|
          next unless value.is_a?(Hash)
          next if NON_MODULE_KEYS.include?(key.to_s)

          fqcn = resolve_fqcn(key.to_s)
          yield(fqcn, AnsibleModule.find_by(fqcn: fqcn), value)
        end
      end
    end

    def resolve_fqcn(key)
      key.include?(".") ? key : "ansible.builtin.#{key}"
    end
  end
end

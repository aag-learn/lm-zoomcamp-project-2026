module Eval
  # One hand-picked task-generation prompt per named module (PLAN.md), run
  # through the live agent loop and checked deterministically — see
  # Eval::CompositionalChecker.
  class CompositionalEvaluator
    PROMPTS = {
      "ansible.builtin.copy" => "create a task to copy a file to the host and set its permissions to 0666",
      "ansible.builtin.service" => "write a task to restart a service only when a config file changes",
      "ansible.builtin.apt" => "write a task to install a package only if not already present",
      "ansible.builtin.apt_key" => "add an apt signing key for a third-party repo",
      "ansible.builtin.user" => "create a task to add a system user with a specific shell and home directory, without a login password",
      "ansible.builtin.iptables" => "write a task to open TCP port 443 on the INPUT chain"
    }.freeze

    def self.call
      new.call
    end

    # Confirmed live (2026-08-18): without this, the agent answers in prose with an
    # unfenced YAML snippet embedded in it, which CompositionalChecker's fenced-block
    # extraction can't isolate from the surrounding text — every answer came back
    # yaml_valid: false, not because the YAML itself was wrong. This instruction is
    # an eval-mechanics concern, kept separate from PROMPTS' documented task wording.
    FORMAT_INSTRUCTION = "Respond with the task YAML in a fenced ```yaml code block."

    def call
      PROMPTS.each_with_index.map do |(fqcn, prompt), index|
        Rails.logger.info("[Eval::CompositionalEvaluator] #{index + 1}/#{PROMPTS.size} #{fqcn}")

        answer = RubyLLM.chat.with_tools(SearchAnsibleDocs.new, GetModuleDetails)
                             .ask("#{prompt}\n\n#{FORMAT_INSTRUCTION}").content
        checks = CompositionalChecker.call(answer)

        { module_fqcn: fqcn, prompt: prompt, answer: answer }.merge(checks)
      end
    end
  end
end

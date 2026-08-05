module Eval
  # The 6 modules ground truth is scoped to, hand-picked for scenario diversity
  # (param count, choice/enum density, suboptions, deprecation status) — see
  # PLAN.md's "Evaluation" section for the full rationale behind each pick.
  # Also drives the compositional task eval (Eval::CompositionalEvaluator),
  # which reuses this same list rather than an independent prompt set.
  NAMED_MODULES = %w[
    ansible.builtin.copy
    ansible.builtin.service
    ansible.builtin.apt
    ansible.builtin.apt_key
    ansible.builtin.user
    ansible.builtin.iptables
  ].freeze
end

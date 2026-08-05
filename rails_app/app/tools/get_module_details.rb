class GetModuleDetails < RubyLLM::Tool
  description "Get the full documentation (all parameters, examples, and return values) for one exact " \
              "Ansible module, given its fully-qualified name."
  param :fqcn, desc: "The fully-qualified module name, e.g. ansible.builtin.copy."

  def execute(fqcn:)
    ansible_module = AnsibleModule.find_by(fqcn: fqcn)
    return "Module #{fqcn} not found." unless ansible_module

    ansible_module.raw_doc.to_json
  end
end

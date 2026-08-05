module MessagesHelper
  def default_model_display_name
    "Default: #{RubyLLM.models.find(RubyLLM.config.default_model).label}"
  end

  # Grouped by module fqcn => [parameter/example/return labels], e.g. {"ansible.builtin.copy" => ["mode", "src"]}.
  # Any stable_id that no longer resolves to a Chunk (removed in a later Ansible release) is silently omitted.
  def citation_groups(retrieval_log)
    return {} if retrieval_log.nil?

    stable_ids = retrieval_log.retrieved_chunks.map { |chunk| chunk["stable_id"] }
    chunks = Chunk.where(stable_id: stable_ids).includes(:ansible_module)

    chunks.group_by { |chunk| chunk.ansible_module.fqcn }
          .transform_values { |group| group.map { |chunk| chunk.stable_id.split("::").last } }
          .sort.to_h
  end
end

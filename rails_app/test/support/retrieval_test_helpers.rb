module RetrievalTestHelpers
  EMBEDDINGS_FIXTURE_PATH = Rails.root.join("test/fixtures/files/embeddings.json")

  def captured_embeddings
    @captured_embeddings ||= JSON.parse(File.read(EMBEDDINGS_FIXTURE_PATH))
  end

  def captured_embedding_for(key)
    captured_embeddings.fetch(key).fetch("embedding")
  end

  def create_module(fqcn)
    AnsibleModule.create!(fqcn: fqcn, ansible_core_version: "2.21.2")
  end

  def create_chunk(ansible_module:, stable_id:, content:, embedding: Array.new(384, 0.0), chunk_type: "parameter")
    ansible_module.chunks.create!(
      chunk_type: chunk_type,
      stable_id: stable_id,
      content: content,
      embedding: embedding,
      ansible_core_version: "2.21.2"
    )
  end
end

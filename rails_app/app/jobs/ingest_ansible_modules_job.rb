class IngestAnsibleModulesJob < ApplicationJob
  queue_as :default

  EMBED_BATCH_SIZE = 500

  def perform(collection: "ansible.builtin")
    fetch_result = AnsibleDocClient.fetch(collection: collection)
    version = fetch_result.ansible_core_version

    module_rows = build_module_rows(fetch_result.modules, version)
    chunks_by_fqcn = build_chunks_by_fqcn(fetch_result.modules)
    embed_all_chunks!(chunks_by_fqcn)

    ActiveRecord::Base.transaction do
      Chunk.delete_all
      AnsibleModule.delete_all

      inserted_modules = AnsibleModule.insert_all!(module_rows, returning: %w[id fqcn])
      fqcn_to_id = inserted_modules.rows.to_h { |id, fqcn| [ fqcn, id ] }

      chunk_rows = build_chunk_rows(chunks_by_fqcn, fqcn_to_id, version)
      Chunk.insert_all!(chunk_rows) if chunk_rows.any?
    end
  end

  private

  def build_module_rows(modules_by_fqcn, version)
    now = Time.current

    modules_by_fqcn.map do |fqcn, raw_doc|
      doc = raw_doc["doc"] || {}

      {
        fqcn: fqcn,
        description: doc["short_description"],
        deprecated: doc.key?("deprecated"),
        raw_doc: raw_doc,
        ansible_core_version: version,
        created_at: now,
        updated_at: now
      }
    end
  end

  def build_chunks_by_fqcn(modules_by_fqcn)
    modules_by_fqcn.to_h do |fqcn, raw_doc|
      [ fqcn, Ingestion::Chunker.call(fqcn, raw_doc) ]
    end
  end

  def embed_all_chunks!(chunks_by_fqcn)
    all_chunks = chunks_by_fqcn.values.flatten

    all_chunks.each_slice(EMBED_BATCH_SIZE) do |batch|
      embeddings = EmbeddingClient.embed(batch.map { |chunk| chunk[:content] })

      batch.zip(embeddings).each do |chunk, embedding|
        chunk[:embedding] = embedding
      end
    end
  end

  def build_chunk_rows(chunks_by_fqcn, fqcn_to_id, version)
    now = Time.current

    chunks_by_fqcn.flat_map do |fqcn, chunks|
      ansible_module_id = fqcn_to_id.fetch(fqcn)

      chunks.map do |chunk|
        {
          ansible_module_id: ansible_module_id,
          chunk_type: chunk[:chunk_type],
          stable_id: chunk[:stable_id],
          content: chunk[:content],
          embedding: chunk[:embedding],
          ansible_core_version: version,
          created_at: now,
          updated_at: now
        }
      end
    end
  end
end

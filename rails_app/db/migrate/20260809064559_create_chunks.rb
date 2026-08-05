class CreateChunks < ActiveRecord::Migration[8.1]
  def change
    create_table :chunks do |t|
      t.references :ansible_module, null: false, foreign_key: true
      t.string :chunk_type, null: false
      t.string :stable_id, null: false
      t.text :content, null: false
      t.vector :embedding, limit: 384, null: false
      t.string :ansible_core_version, null: false

      t.timestamps
    end

    add_index :chunks, :stable_id, unique: true

    reversible do |dir|
      dir.up do
        execute <<~SQL
          ALTER TABLE chunks
          ADD COLUMN search_text tsvector
          GENERATED ALWAYS AS (to_tsvector('english', content)) STORED;
        SQL

        execute "CREATE INDEX index_chunks_on_search_text ON chunks USING gin (search_text);"
      end

      dir.down do
        execute "DROP INDEX index_chunks_on_search_text;"
        execute "ALTER TABLE chunks DROP COLUMN search_text;"
      end
    end
  end
end

class CreateRetrievalLogs < ActiveRecord::Migration[8.1]
  def change
    create_table :retrieval_logs do |t|
      t.references :message, null: false, foreign_key: true, index: { unique: true }
      t.string :retrieval_strategy, null: false
      t.jsonb :retrieved_chunks, null: false, default: []
      t.string :ansible_core_version
      t.decimal :cost
      t.decimal :response_time
      t.integer :input_tokens
      t.integer :output_tokens
      t.string :top_module

      t.timestamps
    end
  end
end

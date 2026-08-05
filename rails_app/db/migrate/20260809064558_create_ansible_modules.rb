class CreateAnsibleModules < ActiveRecord::Migration[8.1]
  def change
    create_table :ansible_modules do |t|
      t.string :fqcn, null: false
      t.text :description
      t.boolean :deprecated, null: false, default: false
      t.jsonb :raw_doc, null: false, default: {}
      t.string :ansible_core_version, null: false

      t.timestamps
    end

    add_index :ansible_modules, :fqcn, unique: true
  end
end

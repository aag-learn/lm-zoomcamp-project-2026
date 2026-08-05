# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_08_09_064559) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "vector"

  create_table "ansible_modules", force: :cascade do |t|
    t.string "ansible_core_version", null: false
    t.datetime "created_at", null: false
    t.boolean "deprecated", default: false, null: false
    t.text "description"
    t.string "fqcn", null: false
    t.jsonb "raw_doc", default: {}, null: false
    t.datetime "updated_at", null: false
    t.index ["fqcn"], name: "index_ansible_modules_on_fqcn", unique: true
  end

  create_table "chunks", force: :cascade do |t|
    t.string "ansible_core_version", null: false
    t.bigint "ansible_module_id", null: false
    t.string "chunk_type", null: false
    t.text "content", null: false
    t.datetime "created_at", null: false
    t.vector "embedding", limit: 384, null: false
    t.virtual "search_text", type: :tsvector, as: "to_tsvector('english'::regconfig, content)", stored: true
    t.string "stable_id", null: false
    t.datetime "updated_at", null: false
    t.index ["ansible_module_id"], name: "index_chunks_on_ansible_module_id"
    t.index ["search_text"], name: "index_chunks_on_search_text", using: :gin
    t.index ["stable_id"], name: "index_chunks_on_stable_id", unique: true
  end

  add_foreign_key "chunks", "ansible_modules"
end

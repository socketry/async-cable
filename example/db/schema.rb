# Released under the MIT License.
# Copyright, 2024-2026, by Samuel Williams.

ActiveRecord::Schema[8.0].define(version: 2024_11_15_075615) do
  create_table "items", force: :cascade do |t|
    t.string "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end
end

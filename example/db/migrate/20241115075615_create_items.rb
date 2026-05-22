# Released under the MIT License.
# Copyright, 2024-2026, by Samuel Williams.

class CreateItems < ActiveRecord::Migration[8.0]
  def change
    create_table :items do |t|
      t.string :name

      t.timestamps
    end
  end
end

# Released under the MIT License.
# Copyright, 2024-2026, by Samuel Williams.

class Item < ApplicationRecord
  after_create_commit -> { broadcast_append_to "items" }
end

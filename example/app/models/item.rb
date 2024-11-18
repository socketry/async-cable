class Item < ApplicationRecord
  after_create_commit -> { broadcast_append_to "items" }
end

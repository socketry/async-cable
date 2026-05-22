# Released under the MIT License.
# Copyright, 2024-2026, by Samuel Williams.

require "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1400 ]
end

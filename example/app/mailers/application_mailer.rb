# Released under the MIT License.
# Copyright, 2024-2026, by Samuel Williams.

class ApplicationMailer < ActionMailer::Base
  default from: "from@example.com"
  layout "mailer"
end

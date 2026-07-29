class ApplicationMailer < ActionMailer::Base
  default from: ENV.fetch('MAILER_FROM', 'tinyrest.app.support@gmail.com')
  layout "mailer"
end

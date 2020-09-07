Rails.application.configure do
  smtp_provider = :mailjet # :sendgrid or :mailjet (fallback)
  smtp_credentials = Rails.application.credentials[Rails.env.to_sym][:smtp][smtp_provider]

  break if smtp_credentials.nil?

  config.action_mailer.smtp_settings = {
    address: smtp_credentials[:address],
    port: smtp_credentials[:port],
    user_name: smtp_credentials[:user_name],
    password: smtp_credentials[:password],
    authentication: :plain
  }

  config.action_mailer.default_url_options = { host: 'makerepo.com' }
end
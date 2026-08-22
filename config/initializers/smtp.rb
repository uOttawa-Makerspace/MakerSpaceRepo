Rails.application.configure do
  smtp_provider = :amazon_ses
  smtp_credentials =
    Rails.application.credentials.dig(Rails.env.to_sym, :smtp, smtp_provider)

  if smtp_credentials.present?
    config.action_mailer.smtp_settings = {
      address: smtp_credentials[:address],
      port: smtp_credentials[:port],
      user_name: smtp_credentials[:user_name],
      password: smtp_credentials[:password],
      authentication: :plain,
      enable_starttls_auto: true
    }

    config.action_mailer.default_url_options = { host: "makerepo.com" }
  end
end
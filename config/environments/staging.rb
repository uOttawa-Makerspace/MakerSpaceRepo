# frozen_string_literal: true

require "active_support/core_ext/integer/time"

Rails.application.configure do
  $n_exams_question = 10

  # Code is not reloaded between requests (Rails 8 syntax)
  config.enable_reloading = false

  # Eager load code on boot.
  config.eager_load = true

  # Full error reports are disabled and caching is turned on.
  config.consider_all_requests_local = false
  config.action_controller.perform_caching = true

  # Enable serving static files from `/public` for Vite and Propshaft
  config.public_file_server.enabled = ENV["RAILS_SERVE_STATIC_FILES"].present? || true
  config.public_file_server.headers = {
    "cache-control" => "public, max-age=31536000, immutable"
  }

  # Logging configuration
  config.log_level = :debug
  config.log_tags = [:request_id]
  config.log_formatter = ::Logger::Formatter.new

  # Stream logs to STDOUT for Docker Compose
  if ENV["RAILS_LOG_TO_STDOUT"].present?
    logger = ActiveSupport::Logger.new(STDOUT)
    logger.formatter = config.log_formatter
    config.logger = ActiveSupport::TaggedLogging.new(logger)
  else
    config.logger = ActiveSupport::Logger.new("#{Rails.root}/log/#{Rails.env}.log")
  end

  # Store uploaded files on Amazon S3
  config.active_storage.service = :amazon

  # Action Mailer
  config.action_mailer.perform_caching = false
  config.action_mailer.default_url_options = { host: "staging.makerepo.com" }
  config.action_mailer.asset_host = "https://staging.makerepo.com"

  # Translations & Deprecations
  config.i18n.fallbacks = true
  config.active_support.deprecation = :notify

  # Schema migrations
  config.active_record.dump_schema_after_migration = false

  Octokit.configure do |c|
    c.client_id =
      Rails.application.credentials.dig(Rails.env.to_sym, :github, :app_key)
    c.client_secret =
      Rails.application.credentials.dig(Rails.env.to_sym, :github, :app_key_secret)
  end
end

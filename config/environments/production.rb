require "active_support/core_ext/integer/time"

Rails.application.configure do
  $n_exams_question = 10
  # Settings specified here will take precedence over those in config/application.rb.

  # Code is not reloaded between requests.
  config.enable_reloading = false

  # Eager load code on boot for threaded web servers.
  config.eager_load = true

  # Full error reports are disabled and caching is turned on.
  config.consider_all_requests_local = false
  config.action_controller.perform_caching = true

  # Ensures that a master key has been made available via ENV["RAILS_MASTER_KEY"] or config/master.key
  config.require_master_key = true

  # Enable serving static files from `/public` (needed for Vite compiled output)
  config.public_file_server.enabled = ENV["RAILS_SERVE_STATIC_FILES"].present? || true
  config.public_file_server.headers = {
    "cache-control" => "public, max-age=31536000, immutable"
  }

  # Store uploaded files on Amazon S3
  config.active_storage.service = :amazon

  # Logging configuration
  config.log_level = :debug
  config.logger = ActiveSupport::Logger.new("#{Rails.root}/log/#{Rails.env}.log")
  config.log_tags = [:request_id]

  # Action Mailer configuration
  config.action_mailer.perform_caching = false
  config.action_mailer.asset_host = "https://makerepo.com"

  # Enable locale fallbacks for I18n
  config.i18n.fallbacks = true

  # Don't log deprecations in production
  config.active_support.report_deprecations = false

  # Use default logging formatter
  config.log_formatter = ::Logger::Formatter.new

  if ENV["RAILS_LOG_TO_STDOUT"].present?
    logger = ActiveSupport::Logger.new(STDOUT)
    logger.formatter = config.log_formatter
    config.logger = ActiveSupport::TaggedLogging.new(logger)
  end

  # Do not dump schema after migrations.
  config.active_record.dump_schema_after_migration = false
end

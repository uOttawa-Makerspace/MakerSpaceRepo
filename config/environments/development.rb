# frozen_string_literal: true

Rails.application.configure do
  $n_exams_question = 3
  # Settings specified here will take precedence over those in config/application.rb.
  config.hosts << "47f4cb4117ff.ngrok.io"
  # In the development environment your application's code is reloaded on
  # every request. This slows down response time but is perfect for development
  # since you don't have to restart the web server when you make code changes.
  config.cache_classes = false

  # Do not eager load code on boot.
  config.eager_load = false

  # Show full error reports.
  config.consider_all_requests_local = true

  # Enable/disable caching. By default caching is disabled.
  # Run rails dev:cache to toggle caching.
  if Rails.root.join('tmp', 'caching-dev.txt').exist?
    config.action_controller.perform_caching = true

    config.cache_store = :memory_store
    config.public_file_server.headers = {
        'Cache-Control' => "public, max-age=#{2.days.to_i}"
    }
  else
    config.action_controller.perform_caching = false

    config.cache_store = :null_store
  end

  # Store uploaded files on the local file system (see config/storage.yml for options)
  config.active_storage.service = :amazon

  # Don't care if the mailer can't send.
  config.action_mailer.raise_delivery_errors = false

  config.action_mailer.perform_caching = false

  # Print deprecation notices to the Rails logger.
  config.active_support.deprecation = :log

  # Raise an error on page load if there are pending migrations.
  config.active_record.migration_error = :page_load

  # Highlight code that triggered database queries in logs.
  config.active_record.verbose_query_logs = true


  # Debug mode disables concatenation and preprocessing of assets.
  # This option may cause significant delays in view rendering with a large
  # number of complex assets.
  config.assets.debug = true

  # Suppress logger output for asset requests.
  config.assets.quiet = true

  config.file_watcher = ActiveSupport::EventedFileUpdateChecker

  # Raises error for missing translations
  # config.action_view.raise_on_missing_translations = true

  config.console = Pry

  Octokit.configure do |c|
    c.client_id        = Rails.application.credentials[Rails.env.to_sym][:github][:app_key]
    c.client_secret    = Rails.application.credentials[Rails.env.to_sym][:github][:app_key_secret]
  end

  # SMTP GMail Settings
  config.action_mailer.perform_caching = false
  config.action_mailer.default_url_options = { host: 'localhost:3000' }

  # Use letter opener to open emails i development mode
  # config.action_mailer.delivery_method = :smtp
  config.action_mailer.delivery_method = :letter_opener
  config.action_mailer.perform_deliveries = true

  # GMAIL SETUP
  config.action_mailer.smtp_settings = {
    address: 'smtp.sendgrid.net',
    port: 587,
    user_name: Rails.application.credentials[Rails.env.to_sym][:smtp_user],
    password: Rails.application.credentials[Rails.env.to_sym][:smtp_password],
    authentication: 'plain',
    enable_starttls_auto: true
  }

  # config.force_ssl = true

  config.paperclip_defaults = {
    storage: :s3,
    s3_region: Rails.application.credentials[Rails.env.to_sym][:aws][:region],
    s3_credentials: {
      bucket: Rails.application.credentials[Rails.env.to_sym][:aws][:bucket_name],
      access_key_id: Rails.application.credentials[Rails.env.to_sym][:aws][:access_key_id],
      secret_access_key: Rails.application.credentials[Rails.env.to_sym][:aws][:secret_access_key]
    }
  }
end

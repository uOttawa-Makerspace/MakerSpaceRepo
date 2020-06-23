# frozen_string_literal: true

Rails.application.configure do
  $n_exams_question = 20
  # Settings specified here will take precedence over those in config/application.rb.

  # Code is not reloaded between requests.
  config.cache_classes = true

  # Eager load code on boot. This eager loads most of Rails and
  # your application in memory, allowing both threaded web servers
  # and those relying on copy on write to perform better.
  # Rake tasks automatically ignore this option for performance.
  config.eager_load = true

  # Full error reports are disabled and caching is turned on.
  config.consider_all_requests_local       = false
  config.action_controller.perform_caching = true

  # Enable Rack::Cache to put a simple HTTP cache in front of your application
  # Add `rack-cache` to your Gemfile before enabling this.
  # For large-scale production use, consider using a caching reverse proxy like
  # NGINX, varnish or squid.
  # config.action_dispatch.rack_cache = true

  # Disable serving static files from the `/public` folder by default since
  # Apache or NGINX already handles this.
  config.public_file_server.enabled = ENV['RAILS_SERVE_STATIC_FILES'].present?

  # Compress JavaScripts and CSS.
  # config.assets.js_compressor = :uglifier
  config.assets.js_compressor = Uglifier.new(harmony: true)
  # config.assets.css_compressor = :sass

  # Do not fallback to assets pipeline if a precompiled asset is missed.
  config.assets.compile = false

  # Asset digests allow you to set far-future HTTP expiration dates on all assets,
  # yet still be able to expire them through the digest params.
  config.assets.digest = true

  # `config.assets.precompile` and `config.assets.version` have moved to config/initializers/assets.rb

  # Specifies the header that your server uses for sending files.
  # config.action_dispatch.x_sendfile_header = 'X-Sendfile' # for Apache
  # config.action_dispatch.x_sendfile_header = 'X-Accel-Redirect' # for NGINX

  # Force all access to the app over SSL, use Strict-Transport-Security, and use secure cookies.
  # config.force_ssl = true

  # Use the lowest log level to ensure availability of diagnostic information
  # when problems arise.
  config.log_level = :debug

  # Prepend all log lines with the following tags.
  # config.log_tags = [ :subdomain, :uuid ]

  # Use a different logger for distributed setups.
  config.logger = Logger.new("#{Rails.root}/log/#{Rails.env}.log")

  # Use a different cache store in production.
  # config.cache_store = :mem_cache_store

  # Enable serving of images, stylesheets, and JavaScripts from an asset server.
  # config.action_controller.asset_host = 'http://assets.example.com'

  # Ignore bad email addresses and do not raise email delivery errors.
  # Set this to true and configure the email server for immediate delivery to raise delivery errors.
  # config.action_mailer.raise_delivery_errors = false

  # Enable locale fallbacks for I18n (makes lookups for any locale fall back to
  # the I18n.default_locale when a translation cannot be found).
  config.i18n.fallbacks = true
  config.active_storage.service = :amazon

  # Send deprecation notices to registered listeners.
  config.active_support.deprecation = :notify

  # Use default logging formatter so that PID and timestamp are not suppressed.
  config.log_formatter = ::Logger::Formatter.new

  # Do not dump schema after migrations.
  config.active_record.dump_schema_after_migration = false

  config.assets.precompile += %w[vendor.js vendor.css]

  Octokit.configure do |c|
    c.client_id        = Rails.application.credentials[Rails.env.to_sym][:github][:app_key]
    c.client_secret    = Rails.application.credentials[Rails.env.to_sym][:github][:app_key_secret]
  end

  # SMTP GMail Settings
  config.action_mailer.default_url_options = { host: 'makerepo.com' }

  config.action_mailer.delivery_method = :smtp

  # GMAIL SETUP
  config.action_mailer.smtp_settings = {
    address: 'smtp.sendgrid.net',
    port: 587,
    user_name: Rails.application.credentials[Rails.env.to_sym][:smtp_user],
    password: Rails.application.credentials[Rails.env.to_sym][:smtp_password],
    authentication: 'plain',
    enable_starttls_auto: true
  }

  config.paperclip_defaults = {
    storage: :s3,
    s3_credentials: {
      bucket: Rails.application.credentials[Rails.env.to_sym][:aws][:bucket_name],
      access_key_id: Rails.application.credentials[Rails.env.to_sym][:aws][:access_key_id],
      secret_access_key: Rails.application.credentials[Rails.env.to_sym][:aws][:secret_access_key],
      s3_region: Rails.application.credentials[Rails.env.to_sym][:aws][:region]
    }
  }
end

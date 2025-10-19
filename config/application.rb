require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module MakerSpaceRepo
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 7.2

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")
    # config.before_configuration do
    #   env_file = File.join(Rails.root, "config", "local_env.yml")
    #   if File.exist?(env_file)
    #     YAML
    #       .safe_load(File.open(env_file))
    #       .each { |key, value| ENV[key.to_s] = value }
    #   end
    # end

    # Settings in config/environments/* take precedence over those specified here.
    # Application configuration can go into files in config/initializers
    # -- all .rb files in that directory are automatically loaded after loading

    # the framework and any gems in your application.
    # Set Time.zone default to the specified zone and make Active Record auto-convert to this zone.
    # Run "rake -D time" for a list of tasks for finding time zone names. Default is UTC.
    config.time_zone = "Eastern Time (US & Canada)"

    config.active_storage.variant_processor = :mini_magick
    # Proxy active storage downloads through the server (and so through the CDN)
    config.active_storage.resolve_model_to_route = :rails_storage_proxy

    # Use a real queuing backend for Active Job (and separate queues per environment).
    config.active_job.queue_adapter = :solid_queue
    # config.solid_queue.connects_to = { database: { writing: :queue } }
    config.solid_queue.logger = ActiveSupport::Logger.new(STDOUT)

    # The default locale is :en and all translations from config/locales/*.rb,yml are auto loaded.
    # config.i18n.load_path += Dir[Rails.root.join('my', 'locales', '*.{rb,yml}').to_s]
    # config.i18n.default_locale = :de
  end
end

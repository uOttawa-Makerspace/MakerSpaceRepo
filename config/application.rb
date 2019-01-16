require File.expand_path('../boot', __FILE__)

require 'csv'
require 'rails/all'

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module MakerSpaceRepo
  class Application < Rails::Application
    # Settings in config/environments/* take precedence over those specified here.
    # Application configuration should go into files in config/initializers
    # -- all .rb files in that directory are automatically loaded.

    # Set Time.zone default to the specified zone and make Active Record auto-convert to this zone.
    # Run "rake -D time" for a list of tasks for finding time zone names. Default is UTC.
    config.time_zone = 'Eastern Time (US & Canada)'

    # The default locale is :en and all translations from config/locales/*.rb,yml are auto loaded.
    # config.i18n.load_path += Dir[Rails.root.join('my', 'locales', '*.{rb,yml}').to_s]
    # config.i18n.default_locale = :de

    # Do not swallow errors in after_commit/after_rollback callbacks.
    config.active_record.raise_in_transactional_callbacks = true

    SamlIdp.configure do |config|
      config.x509_certificate = IO.read "certs/saml.crt"

      config.secret_key = IO.read "certs/saml.key"

      service_providers = {
          "wiki.makerepo.com" => {
              response_hosts: ["wiki.makerepo.com", "staff.makerepo.com"]
          }
      }

      config.name_id.formats = {
          email_address: -> (p) { p.email },
          transient: -> (p) { p.username },
          persistent: -> (p) { p.username }
      }

      config.attributes = {
          "email_address": {
              :getter => -> (p) { p.email }
          },
          "username": {
              :getter => -> (p) { p.username }
          },
          "name": {
              :getter => -> (p) { p.name }
          },
          "is_staff": {
              :getter => -> (p) { p.staff? }
          },
          "is_admin": {
              :getter => -> (p) { p.admin? }
          }
      }

      config.service_provider.metadata_persister = ->(identifier, settings) {
        fname = identifier.to_s.gsub(/\/|:/,"_")
        FileUtils.mkdir_p(Rails.root.join('cache', 'saml', 'metadata').to_s)
        File.open Rails.root.join("cache/saml/metadata/#{fname}"), "r+b" do |f|
          Marshal.dump settings.to_h, f
        end
      }

      # `identifier` is the entity_id or issuer of the Service Provider,
      # `service_provider` is a ServiceProvider object. Based on the `identifier` or the
      # `service_provider` you should return the settings.to_h from above
      config.service_provider.persisted_metadata_getter = ->(identifier, service_provider){
        fname = identifier.to_s.gsub(/\/|:/,"_")
        FileUtils.mkdir_p(Rails.root.join('cache', 'saml', 'metadata').to_s)
        full_filename = Rails.root.join("cache/saml/metadata/#{fname}")
        if File.file?(full_filename)
          File.open full_filename, "rb" do |f|
            Marshal.load f
          end
        end
      }

      config.service_provider.finder = ->(issuer_or_entity_id) do
        service_providers[issuer_or_entity_id]
      end
    end
  end
end

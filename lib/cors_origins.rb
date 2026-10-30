# frozen_string_literal: true

# Origins allowed to call this app from a browser with CORS
# (config/initializers/cors.rb), per environment. Every origin is an exact string
# (scheme included) or a fully anchored regexp (\A...\z), so look-alikes such as
# app.makerepo.com.attacker.io cannot match.
#
# app_origins is used for the credentialed catch-all (cookie session; with the
# legacy JSON CSRF exemption an allowed origin can act as the signed-in user) and
# for /api (Bearer tokens). So it is as narrow as each environment allows:
# - production: the staff app and Design Day only;
# - staging: those plus the Cloudflare Pages previews (previews point to staging);
# - development/test: those plus the Vite dev server on localhost:5173.
module CorsOrigins
  PRODUCTION = [
    "https://app.makerepo.com",
    "https://designday.makerepo.com"
  ].freeze

  PREVIEWS = [
    %r{\Ahttps://([a-z0-9-]+\.)+makerepo-app\.pages\.dev\z},
    %r{\Ahttps://([a-z0-9-]+\.)+design-day-react\.pages\.dev\z}
  ].freeze

  LOCAL_DEV_SERVERS = [
    "http://localhost:5173",
    "https://localhost:5173"
  ].freeze

  module_function

  def app_origins(env = Rails.env)
    env = ActiveSupport::EnvironmentInquirer.new(env.to_s)
    origins = PRODUCTION.dup
    origins += PREVIEWS if env.staging?
    origins += LOCAL_DEV_SERVERS if env.local?
    origins.freeze
  end
end

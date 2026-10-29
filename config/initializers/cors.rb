# Every origin is either an exact string (scheme included) or a fully anchored
# regexp (\A...\z), so look-alikes such as app.makerepo.com.attacker.io cannot match.
cors_origins = [
  "http://localhost:5173",
  "https://localhost:5173",
  "https://uottawa-makerspace.github.io",
  "https://designday.makerepo.com",
  %r{\Ahttps://([a-z0-9-]+\.)+design-day-react\.pages\.dev\z},
  "https://app.makerepo.com",
  %r{\Ahttps://([a-z0-9-]+\.)+makerepo-app\.pages\.dev\z}
].freeze

# GET /api/v1/design_day is public data for the Design Day app only: it answers just these
# origins (not the staff app, not localhost), and no other CORS block may answer that path.
design_day_origins = [
  "https://designday.makerepo.com",
  %r{\Ahttps://([a-z0-9-]+\.)+design-day-react\.pages\.dev\z}
]
# Local development only (never production): the Design Day app runs on Create React App,
# which uses :3000, or :3001 when this Rails server already holds :3000.
design_day_origins += ["http://localhost:3000", "http://localhost:3001"] if Rails.env.local?
design_day_origins.freeze
design_day_path = %r{\A/api/v1/design_day/?\z}
not_design_day_path = %r{\A(?!/api/v1/design_day/?\z)}

Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins(*design_day_origins)

    resource design_day_path,
             headers: %w[Content-Type],
             methods: %i[get options],
             credentials: false,
             max_age: 600
  end

  # /api/* (JSON API, Bearer tokens): no cookies, so no credentials. Listed first
  # because rack-cors uses the first block whose origin AND path match, so the
  # catch-all block below never answers an /api request with credentials.
  allow do
    origins(*cors_origins)

    resource %r{\A/api/(?!v1/design_day/?\z)},
             headers: %w[Authorization Content-Type X-Refresh-Token],
             methods: %i[get post put patch delete options],
             # Response headers the apps may read cross-origin (GET /api/v1/spaces/:id/shifts).
             expose: %w[X-Truncated],
             credentials: false,
             max_age: 600
  end

  allow do
    origins(*cors_origins)

    resource not_design_day_path,
             headers: :any,
             methods: %i[get post put patch delete options head],
             credentials: true
  end
end

# Every origin is either an exact string (scheme included) or a fully anchored
# regexp (\A...\z), so look-alikes such as app.makerepo.com.attacker.io cannot match.
Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins "http://localhost:5173",
            "https://localhost:5173",
            "https://uottawa-makerspace.github.io",
            "https://designday.makerepo.com",
            %r{\Ahttps://([a-z0-9-]+\.)+design-day-react\.pages\.dev\z},
            "https://app.makerepo.com",
            %r{\Ahttps://([a-z0-9-]+\.)+makerepo-app\.pages\.dev\z}

    resource "*",
             headers: :any,
             methods: %i[get post put patch delete options head],
             credentials: true
  end
end

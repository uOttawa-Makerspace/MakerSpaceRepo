Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins "localhost:5173",
            "uottawa-makerspace.github.io/makerepo-react-app",
            "uottawa-makerspace.github.io",
            "designday.makerepo.com",
            %r{https://.*\.design-day-react.pages.dev},
            "app.makerepo.com",
            %r{https://.*\.makerepo-app.pages.dev}

    resource "*",
             headers: :any,
             methods: %i[get post put patch delete options head],
             credentials: true
  end
end

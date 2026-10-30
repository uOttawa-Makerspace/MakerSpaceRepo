# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("lib/cors_origins")

# The credentialed CORS allow-list per environment (config/initializers/cors.rb).
# With cookie sessions and the legacy JSON CSRF exemption, an allowed origin can
# act as the signed-in user, so production allows only the staff app.
RSpec.describe CorsOrigins do
  def allowed?(origins, origin)
    origins.any? { |o| o.is_a?(Regexp) ? o.match?(origin) : o == origin }
  end

  let(:apps) { ["https://app.makerepo.com"] }
  let(:locals) { ["http://localhost:5173", "https://localhost:5173"] }
  let(:previews) { ["https://abc123.makerepo-app.pages.dev"] }
  # Design Day never sends cookies (any branch): it is answered only by the
  # non-credentialed /api/v1/design_day block, as are its previews.
  let(:never) do
    ["https://designday.makerepo.com", "https://feature-x.design-day-react.pages.dev",
     "https://uottawa-makerspace.github.io", "https://app.makerepo.com.attacker.io", "http://app.makerepo.com"]
  end

  it "production: the staff app only" do
    origins = described_class.app_origins("production")
    expect(apps).to all(satisfy { |o| allowed?(origins, o) })
    (locals + previews + never).each { |o| expect(allowed?(origins, o)).to be(false), o }
  end

  it "staging: plus the Pages previews, no localhost" do
    origins = described_class.app_origins("staging")
    (apps + previews).each { |o| expect(allowed?(origins, o)).to be(true), o }
    (locals + never).each { |o| expect(allowed?(origins, o)).to be(false), o }
  end

  %w[development test].each do |env|
    it "#{env}: plus the Vite dev server on localhost:5173, no previews" do
      origins = described_class.app_origins(env)
      (apps + locals).each { |o| expect(allowed?(origins, o)).to be(true), o }
      (previews + never).each { |o| expect(allowed?(origins, o)).to be(false), o }
    end
  end

  it "the initializer's credentialed and /api blocks use this list" do
    cors = Rails.application.config.middleware.find { |m| m.klass == Rack::Cors }
    expect(cors).to be_present
    expect(File.read(Rails.root.join("config/initializers/cors.rb"))).to include("cors_origins = CorsOrigins.app_origins")
  end
end

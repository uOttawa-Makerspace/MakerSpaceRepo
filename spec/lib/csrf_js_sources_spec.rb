# frozen_string_literal: true

require "rails_helper"

# The page's CSRF token is read in one place, app/javascript/src/csrf.js
# (csrfToken / csrfHeaders). Hand-built copies drift (wrong selector, a token on
# a GET); this pins that no other JS source reads or sends it itself.
RSpec.describe "JS CSRF token handling" do
  let(:helper) { Rails.root.join("app/javascript/src/csrf.js") }
  let(:sources) do
    Dir[Rails.root.join("app/javascript/**/*.{js,jsx,ts,tsx}")].map { |f| Pathname(f) } - [helper]
  end

  it "only src/csrf.js reads the csrf-token meta tag or sets the token" do
    offenders = sources.select { |f| f.read.match?(/csrf-token|X-CSRF-Token|authenticity_token/) }
    expect(offenders.map { |f| f.relative_path_from(Rails.root).to_s }).to eq([])
  end
end

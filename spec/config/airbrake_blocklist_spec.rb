# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Airbrake blocklist" do
  let(:keys) { Rails.application.config.x.airbrake_blocklist_keys }

  %w[password refresh_token access_token Authorization X-Refresh-Token HTTP_AUTHORIZATION token].each do |name|
    it "filters #{name}" do
      expect(keys.any? { |re| re.match?(name) }).to be(true)
    end
  end

  it "does not filter ordinary params" do
    expect(keys.any? { |re| re.match?("username") }).to be(false)
  end
end

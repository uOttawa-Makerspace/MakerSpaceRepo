# frozen_string_literal: true

require "rails_helper"

RSpec.describe ServerDateHeader do
  include ActiveSupport::Testing::TimeHelpers

  def answer(headers = {})
    described_class.new(->(_env) { [200, Rack::Headers.new.merge(headers), ["ok"]] }).call({})
  end

  it "sends the server's now as the Date when the app sets none" do
    status, headers, body = travel_to(Time.utc(2026, 1, 1, 12)) { answer("set-cookie" => "a=1") }

    expect([status, body]).to eq([200, ["ok"]])
    expect(headers["date"]).to eq("Thu, 01 Jan 2026 12:00:00 GMT")
    expect(headers["set-cookie"]).to eq("a=1")
  end

  it "keeps a Date the app set" do
    headers = travel_to(Time.utc(2026, 1, 1, 12)) { answer("date" => "Tue, 16 Mar 2027 16:00:00 GMT")[1] }

    expect(headers["date"]).to eq("Tue, 16 Mar 2027 16:00:00 GMT")
  end
end

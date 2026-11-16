# frozen_string_literal: true

require "rails_helper"

RSpec.describe "public/robots.txt" do
  let(:lines) { Rails.public_path.join("robots.txt").read.lines.map(&:strip) }

  it "keeps crawlers off the rewards page and its old /cc_moneys address" do
    expect(lines).to include("Disallow: /rewards", "Disallow: /cc_moneys")
  end
end

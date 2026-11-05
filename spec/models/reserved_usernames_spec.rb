# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Reserved usernames" do
  def first_segments
    Rails.application.routes.routes.filter_map do |route|
      segment = route.path.spec.to_s.delete_prefix("/").split("/").first.to_s.sub(/\(.*/, "")
      segment unless segment.empty? || segment.start_with?(":", "*")
    end.uniq
  end

  it "covers the first static segment of every route" do
    missing = first_segments.reject { |segment| ReservedUsernames.include?(segment) }
    expect(missing).to be_empty
    expect(ReservedUsernames.all).to include("admin", "search", "faq", "help", "login", "staff", "settings")
  end

  describe "User validation" do
    it "rejects a new user named like a route, whatever the case" do
      %w[admin Search FAQ staff Settings].each do |name|
        user = build(:user, :regular_user, username: name)
        expect(user).not_to be_valid
        expect(user.errors[:username]).to eq(["is reserved"])
      end
    end

    it "rejects changing an existing user to a reserved name" do
      user = create(:user, :regular_user)
      expect(user.update(username: "Help")).to be(false)
      expect(user.errors[:username]).to eq(["is reserved"])
      expect(user.reload.username).not_to eq("Help")
    end

    it "accepts an unrelated name and leaves existing users alone" do
      expect(build(:user, :regular_user, username: "jessjourney")).to be_valid
      user = create(:user, :regular_user)
      user.update_columns(username: "explore")
      expect(user.reload.update(name: "Renamed")).to be(true)
      expect(user.reload.name).to eq("Renamed")
      expect(user.username).to eq("explore")
    end
  end

  # The app is only an identity provider (SAML): accounts are never created from
  # an assertion, so no username is derived there.
end

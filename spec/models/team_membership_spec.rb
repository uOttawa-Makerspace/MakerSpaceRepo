# frozen_string_literal: true

require "rails_helper"

RSpec.describe TeamMembership, type: :model do
  let(:team) { Team.create!(name: "T") }
  let(:user) { create(:user) }

  it "has regular_member (default), lead and captain roles with prefixed predicates" do
    expect(TeamMembership.roles.keys).to eq(%w[regular_member lead captain])
    membership = TeamMembership.create!(team: team, user: user)
    expect(membership).to be_role_regular_member
    membership.update!(role: :lead)
    expect(membership).to be_role_lead
  end

  it "allows one membership per user per team" do
    TeamMembership.create!(team: team, user: user)
    dup = TeamMembership.new(team: team, user: user)
    expect(dup).not_to be_valid
    expect(TeamMembership.new(team: Team.create!(name: "U"), user: user)).to be_valid
  end

  it "allows only one captain per team" do
    TeamMembership.create!(team: team, user: user, role: :captain)
    second = TeamMembership.new(team: team, user: create(:user), role: :captain)
    expect(second).not_to be_valid
    expect(second.errors[:role]).to include("has already been taken")
    expect(TeamMembership.new(team: team, user: create(:user), role: :lead)).to be_valid
  end

  it "rejects an unknown role with ArgumentError" do
    expect { TeamMembership.new(role: "boss") }.to raise_error(ArgumentError)
  end

  it "does not require user or team (both optional)" do
    expect(TeamMembership.new).to be_valid
  end
end

# frozen_string_literal: true

require "rails_helper"

RSpec.describe Team, type: :model do
  it { should have_many(:team_memberships).dependent(:destroy) }
  it { should have_many(:members).through(:team_memberships) }

  it "requires a name with a custom message" do
    team = Team.new(name: "")
    expect(team).not_to be_valid
    expect(team.errors[:name]).to eq(["A team name is required."])
  end

  it "allows duplicate team names" do
    Team.create!(name: "Same")
    expect(Team.new(name: "Same")).to be_valid
  end

  describe "#captain" do
    let(:team) { Team.create!(name: "T") }

    it "is nil without a captain membership" do
      TeamMembership.create!(team: team, user: create(:user), role: :lead)
      expect(team.captain).to be_nil
    end

    it "returns the captain's user" do
      user = create(:user)
      TeamMembership.create!(team: team, user: user, role: :captain)
      expect(team.captain).to eq(user)
    end
  end

  it "destroys memberships with the team" do
    team = Team.create!(name: "T")
    TeamMembership.create!(team: team, user: create(:user))
    expect { team.destroy }.to change(TeamMembership, :count).by(-1)
  end
end

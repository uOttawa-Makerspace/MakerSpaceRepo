# frozen_string_literal: true

require "rails_helper"

# Admin::TeamsController (teams + memberships). Non-admins bounce to "/".
# Note: there is no destroy route/action for teams.

RSpec.describe "Admin teams", type: :request do
  include SpacesSpecHelpers

  let!(:captain) { create(:user, :staff) }
  let!(:member) { create(:user, :regular_user) }
  let!(:team) do
    Team.create!(name: "Alpha").tap { |t| TeamMembership.create!(team: t, user: captain, role: :captain) }
  end

  def role_of(user)
    TeamMembership.find_by(team: team, user: user)&.role
  end

  describe "role matrix" do
    let(:calls) do
      {
        index: -> { get admin_teams_path },
        show: -> { get admin_team_path(team) },
        new: -> { get new_admin_team_path },
        edit: -> { get edit_admin_team_path(team) },
        create: -> { post admin_teams_path, params: { team: { name: "X" }, captain: member.id } },
        update: -> { patch admin_team_path(team), params: { team: { name: "X" }, captain: captain.id } },
        add: -> { patch add_member_admin_team_path(team, member_id: member.id), params: { role: "lead" } },
        promote: -> { patch promote_member_admin_team_path(team, member_id: member.id) },
        demote: -> { patch demote_member_admin_team_path(team, member_id: member.id) },
        remove: -> { delete remove_member_admin_team_path(team, member_id: member.id) }
      }
    end

    %i[guest regular staff].each do |role|
      it "bounces #{role} to / without changes" do
        expect_bounced(role, calls, state: -> { [Team.order(:id).map(&:attributes), TeamMembership.order(:id).map(&:attributes)] })
      end
    end
  end

  context "as admin" do
    before { sign_in_as(:admin) }

    it "renders index, show, new and edit" do
      get admin_teams_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Alpha")
      get admin_team_path(team)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Team ##{team.id} - Alpha", captain.name)
      get new_admin_team_path
      expect(response).to have_http_status(:ok)
      get edit_admin_team_path(team)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("#{captain.name} (#{captain.username})")
    end

    it "show redirects to the index when the team is unknown" do
      get admin_team_path(0)
      expect(response).to redirect_to(admin_teams_path)
      expect(flash[:alert]).to eq("Could not find team")
    end

    describe "create" do
      it "creates the team and makes the chosen user its captain" do
        expect { post admin_teams_path, params: { team: { name: "Beta" }, captain: member.id } }
          .to change(Team, :count).by(1).and change(TeamMembership, :count).by(1)
        expect(response).to redirect_to(admin_teams_path)
        expect(flash[:notice]).to eq("Successfully created team")
        expect(Team.find_by!(name: "Beta").captain).to eq(member)
      end

      it "requires a captain" do
        expect { post admin_teams_path, params: { team: { name: "Beta" } } }.not_to change(Team, :count)
        expect(response).to redirect_to(new_admin_team_path)
        expect(flash[:alert]).to eq("Please select a captain")
      end

      it "rejects a blank name" do
        expect { post admin_teams_path, params: { team: { name: "" }, captain: member.id } }.not_to change(Team, :count)
        expect(response).to redirect_to(new_admin_team_path)
        expect(flash[:alert]).to eq("Something went wrong while creating the team")
      end
    end

    describe "update" do
      it "renames and hands the captaincy over, demoting the old captain to lead" do
        TeamMembership.create!(team: team, user: member, role: :regular_member)
        patch admin_team_path(team), params: { team: { name: "Alpha2" }, captain: member.id }
        expect(response).to redirect_to(admin_teams_path)
        expect(flash[:notice]).to eq("Successfully updated team")
        expect(team.reload.name).to eq("Alpha2")
        expect(role_of(member)).to eq("captain")
        expect(role_of(captain)).to eq("lead")
      end

      it "keeps roles when the captain is unchanged" do
        patch admin_team_path(team), params: { team: { name: "Alpha3" }, captain: captain.id }
        expect(role_of(captain)).to eq("captain")
        expect(team.reload.name).to eq("Alpha3")
      end

      it "redirects to edit with an alert for a blank name" do
        patch admin_team_path(team), params: { team: { name: "" }, captain: captain.id }
        expect(response).to redirect_to(edit_admin_team_path)
        expect(flash[:alert]).to eq("Something went wrong when trying to update the team.")
        expect(team.reload.name).to eq("Alpha")
      end

      # WART(D-SP08): update without a (valid member) captain param renames the team, demotes the captain, then 500s: team left captain-less.
      it "500s after demoting the captain when captain is missing or not a member" do
        patch admin_team_path(team), params: { team: { name: "Alpha4" } }
        expect(response).to have_http_status(:internal_server_error)
        expect(team.reload.name).to eq("Alpha4")
        expect(role_of(captain)).to eq("lead")
        expect(team.captain).to be_nil
      end
    end

    describe "members" do
      it "adds a member with the given role" do
        patch add_member_admin_team_path(team, member_id: member.id), params: { role: "lead" }
        expect(response).to redirect_to(admin_team_path(team.id))
        expect(flash[:notice]).to eq("Successfully added user.")
        expect(role_of(member)).to eq("lead")
      end

      it "refuses a second captain and a duplicate member" do
        patch add_member_admin_team_path(team, member_id: member.id), params: { role: "captain" }
        expect(flash[:alert]).to eq("Something went wrong while trying to add the user.")
        expect(role_of(member)).to be_nil
        patch add_member_admin_team_path(team, member_id: captain.id), params: { role: "lead" }
        expect(flash[:alert]).to eq("Something went wrong while trying to add the user.")
      end

      # WART(D-SP09): an unknown role value raises ArgumentError from the enum: 500 instead of a flash.
      it "add_member 500s for an unknown role" do
        patch add_member_admin_team_path(team, member_id: member.id), params: { role: "boss" }
        expect(response).to have_http_status(:internal_server_error)
      end

      it "redirects to the index when the team or member is unknown" do
        patch add_member_admin_team_path(0, member_id: member.id), params: { role: "lead" }
        expect(response).to redirect_to(admin_teams_path)
        expect(flash[:alert]).to eq("Could not find team")
        patch add_member_admin_team_path(team, member_id: 0), params: { role: "lead" }
        expect(response).to redirect_to(admin_teams_path)
        expect(flash[:alert]).to eq("Couldn't find member")
      end

      it "promotes regular members to lead only, and demotes leads to regular only" do
        TeamMembership.create!(team: team, user: member, role: :regular_member)
        patch promote_member_admin_team_path(team, member_id: member.id)
        expect(flash[:notice]).to eq("Successfully promoted member.")
        expect(role_of(member)).to eq("lead")
        patch promote_member_admin_team_path(team, member_id: member.id)
        expect(flash[:alert]).to eq("Something went wrong while promoting the team member. You can only promote regular team members.")
        patch demote_member_admin_team_path(team, member_id: member.id)
        expect(flash[:notice]).to eq("Successfully demoted member.")
        expect(role_of(member)).to eq("regular_member")
        patch demote_member_admin_team_path(team, member_id: member.id)
        expect(flash[:alert]).to eq("Something went wrong while demoting the team member. You can only demote team leads.")
        patch demote_member_admin_team_path(team, member_id: captain.id)
        expect(role_of(captain)).to eq("captain")
      end

      it "reports users who are not on the team" do
        [
          -> { patch promote_member_admin_team_path(team, member_id: member.id) },
          -> { patch demote_member_admin_team_path(team, member_id: member.id) },
          -> { delete remove_member_admin_team_path(team, member_id: member.id) }
        ].each do |call|
          call.call
          expect(response).to redirect_to(admin_team_path(team.id))
          expect(flash[:alert]).to eq("Couldn't find the user in the team.")
        end
      end

      it "removes a member but never the captain" do
        TeamMembership.create!(team: team, user: member, role: :regular_member)
        delete remove_member_admin_team_path(team, member_id: member.id)
        expect(flash[:notice]).to eq("Successfully removed the member from the team.")
        expect(role_of(member)).to be_nil
        delete remove_member_admin_team_path(team, member_id: captain.id)
        expect(flash[:alert]).to eq("You can't remove the captain.")
        expect(role_of(captain)).to eq("captain")
      end
    end
  end
end

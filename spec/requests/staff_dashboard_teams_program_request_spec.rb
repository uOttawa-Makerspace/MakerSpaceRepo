# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Staff dashboard add_signed_in_users_to_teams", type: :request do
  let!(:space) { create(:space, name: "JMTS") }
  let!(:newcomer) { create(:user, :regular_user) }
  let!(:member) { create(:user, :regular_user) }

  before do
    [newcomer, member].each { |u| create(:lab_session, space: space, user: u, sign_in_time: 1.hour.ago, sign_out_time: 2.hours.from_now) }
    create(:program, :teams_program, user: member)
  end

  it "adds every signed-in user to the Teams Program once and keeps existing rows" do
    existing = member.programs.sole
    sign_in_as(:staff, space: space)

    expect { patch staff_dashboard_add_signed_in_users_to_teams_path }.to change(Program, :count).by(1)

    expect(flash[:notice]).to eq("Successfully added all users to teams program")
    expect(newcomer.programs.pluck(:program_type)).to eq([Program::TEAMS])
    expect(member.programs.sole.id).to eq(existing.id)
  end

  it "does nothing outside the JMTS space" do
    space.update!(name: "Other Space")
    sign_in_as(:staff, space: space)

    expect { patch staff_dashboard_add_signed_in_users_to_teams_path }.not_to change(Program, :count)
    expect(flash[:alert]).to eq("You can't perform this operation in this space.")
  end
end

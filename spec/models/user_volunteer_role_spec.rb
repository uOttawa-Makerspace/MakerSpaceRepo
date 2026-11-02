# frozen_string_literal: true

require "rails_helper"

# Chunk 13: program-based role derivation as it affects volunteer access.
RSpec.describe User, "volunteer derivation", type: :model do
  it "volunteer? / volunteer_program? depend on a Volunteer Program row, not users.role" do
    role_only = create(:user, :volunteer)
    expect([role_only.role, role_only.volunteer?, role_only.volunteer_program?]).to eq(["volunteer", false, false])
    regular = create(:user, :regular_user)
    Program.create!(user: regular, program_type: Program::VOLUNTEER)
    expect([regular.role, regular.volunteer?, regular.volunteer_program?]).to eq(["regular_user", true, true])
  end

  it "ignores the program's active flag and other program types" do
    inactive = create(:user, :unactive_volunteer_with_volunteer_program)
    expect(inactive.volunteer?).to be(true)
    dev = create(:user, :volunteer_with_dev_program)
    expect(dev.volunteer?).to be(false)
    expect(dev.dev_program?).to be(true)
  end

  it "staff/admin are not volunteers unless enrolled (access code ORs them in separately)" do
    expect(create(:user, :staff).volunteer?).to be(false)
    expect(create(:user, :admin).volunteer?).to be(false)
  end

  it "a guest User.new is not a volunteer" do
    expect(User.new.volunteer?).to be(false)
  end

  it "User.volunteers joins programs of type Volunteer only" do
    v = create(:user, :volunteer_with_volunteer_program)
    create(:user, :volunteer_with_dev_program)
    create(:user, :regular_user)
    expect(User.volunteers).to eq([v])
  end

  it "return_program_status reports the volunteer flag" do
    expect(create(:user, :volunteer_with_volunteer_program).return_program_status).to include(volunteer: true, dev: false)
  end

  it "a user cannot join the Volunteer Program twice" do
    user = create(:user, :volunteer_with_volunteer_program)
    dup = Program.new(user: user, program_type: Program::VOLUNTEER)
    expect(dup).not_to be_valid
    expect(dup.errors[:user]).to eq(["An user can only join a program once"])
  end

  it "get_volunteer_tasks_from_volunteer_joins returns tasks of active joins only; update_wallet stores the CC total" do
    user = create(:user, :volunteer_with_volunteer_program)
    task = create(:volunteer_task)
    create(:volunteer_task_join, :active, user: user, volunteer_task: task)
    create(:volunteer_task_join, :not_active, user: user)
    expect(user.get_volunteer_tasks_from_volunteer_joins).to eq([task])
    create(:cc_money, user: user, cc: 15)
    user.update_wallet
    expect(user.reload.wallet).to eq(15)
  end
end

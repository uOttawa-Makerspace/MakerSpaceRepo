# frozen_string_literal: true

require "rails_helper"
require "rake"

RSpec.describe "move_volunteer_to_volunteer_program:move" do
  before(:all) do
    Rails.application.load_tasks unless Rake::Task.task_defined?("move_volunteer_to_volunteer_program:move")
  end

  def run_task
    task = Rake::Task["move_volunteer_to_volunteer_program:move"]
    task.reenable
    task.invoke
  end

  it "gives a volunteer-role user the Volunteer Program and the regular role" do
    user = create(:user, role: "volunteer")

    run_task

    expect(user.reload.role).to eq("regular_user")
    expect(user.programs.pluck(:program_type, :active)).to eq([[Program::VOLUNTEER, true]])
  end

  it "keeps an existing program row as it is and is safe to run twice" do
    user = create(:user, role: "volunteer")
    existing = create(:program, :volunteer_program, user: user, active: false)

    run_task
    run_task

    expect(user.reload.role).to eq("regular_user")
    expect(user.programs.sole.attributes).to eq(existing.reload.attributes)
  end
end

# frozen_string_literal: true

require "rails_helper"
require "rake"

# The same user and task can have several ended joins (left, then removed, then completed...). The task is counted
# once per join, which changes nothing: the volunteer is active when any of their tasks is completed.
RSpec.describe "active_volunteers:check_volunteers_tasks_performance" do
  let(:user) { create(:user, :volunteer_with_volunteer_program) }

  before do
    Rails.application.load_tasks unless Rake::Task.task_defined?("active_volunteers:check_volunteers_tasks_performance")
    Rake::Task["active_volunteers:check_volunteers_tasks_performance"].reenable
  end

  def program_active = user.programs.find_by(program_type: Program::VOLUNTEER).active

  it "treats a volunteer with two ended joins on a completed task as active" do
    task = create(:volunteer_task, status: "completed")
    create(:volunteer_task_join, :left, volunteer_task: task, user: user)
    create(:volunteer_task_join, :completed, volunteer_task: task, user: user)
    user.programs.find_by(program_type: Program::VOLUNTEER).update!(active: false)

    Rake::Task["active_volunteers:check_volunteers_tasks_performance"].invoke

    expect(program_active).to be(true)
  end

  it "treats a volunteer with two ended joins on an open task as inactive" do
    task = create(:volunteer_task, status: "open")
    create(:volunteer_task_join, :left, volunteer_task: task, user: user)
    create(:volunteer_task_join, :not_active, volunteer_task: task, user: user)

    Rake::Task["active_volunteers:check_volunteers_tasks_performance"].invoke

    expect(program_active).to be(false)
  end
end

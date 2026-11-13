# frozen_string_literal: true

require "rails_helper"

# The my tasks page reads each in-progress task's space, required trainings and the user's pending
# request; with Bullet raising under CI=1 a page of several tasks that loads these one task at a time fails.
RSpec.describe "My volunteer tasks page", type: :request do
  include ContentSpecHelpers

  let(:volunteer) { create(:user, :volunteer_with_volunteer_program) }

  it "renders several in-progress tasks without a query per task" do
    tasks = Array.new(3) do |i|
      task = create(:volunteer_task, title: "Task number #{i}", space: create(:space))
      create(:volunteer_task_join, :active, volunteer_task: task, user: volunteer)
      create(:require_training, volunteer_task: task, training: create(:training))
      task
    end
    create(:volunteer_task_request, :not_processed, volunteer_task: tasks.first, user: volunteer)
    vol_login!(volunteer)

    get my_tasks_volunteer_tasks_path

    expect(response).to have_http_status(:ok)
    expect(response.body.scan(/Task number \d/i).size).to eq(3)
    expect(response.body.scan("Under Review").size).to eq(1)
    expect(response.body.scan("Submit Complete").size).to eq(2)
  end
end

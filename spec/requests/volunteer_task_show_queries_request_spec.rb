# frozen_string_literal: true

require "rails_helper"

# A volunteer task's page does not depend on how many badges the viewer holds: the number of queries stays the same
# from two badges to five, and a badge earned through a proficient project (which has no training session) is shown
# like any other. The counts start at two badges: with one, the query cache can hide a repeated read.
RSpec.describe "Volunteer task page: queries", type: :request do
  let(:volunteer) { create(:user, :volunteer_with_volunteer_program) }
  let(:task) { create(:volunteer_task, title: "Setup crew", space: create(:space)) }

  # Each badge from its own training session, so no read of one is answered from the query cache.
  def badges!(count)
    count.times do
      session = create(:training_session, training: create(:training), level: "Beginner", user: create(:user, :staff))
      Certification.create!(user: volunteer, training_session: session, level: "Beginner")
    end
  end

  def queries_for(path)
    get path
    count_queries { get path }
  end

  before { vol_login!(volunteer) }

  it "runs the same number of queries for a viewer with two badges as with five" do
    badges!(2)
    two = queries_for(volunteer_task_path(task))
    badges!(3)
    five = queries_for(volunteer_task_path(task))

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Setup crew")
    expect(five).to eq(two)
  end

  it "shows the task to a viewer holding a badge earned through a proficient project" do
    cert = Certification.create!(user: volunteer, level: "Beginner")
    create(:proficient_project_session, certification: cert, proficient_project: create(:proficient_project),
                                        user: create(:user, :staff), level: "Beginner")

    get volunteer_task_path(task)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Setup crew")
  end
end

# frozen_string_literal: true

require "rails_helper"

# The profile skills tab and the volunteer stats page show, for every training, the proficient
# projects awarded, the learning modules completed and the recommended hours. The queries on those
# tables must not grow with the number of trainings listed.
RSpec.describe "Training progress on profile and volunteer stats pages", type: :request do
  include ContentSpecHelpers

  PROGRESS_TABLES = /FROM "(proficient_projects|learning_modules|order_items|learning_module_tracks)"/

  let(:user) { create(:user, :volunteer_with_volunteer_program) }
  let(:skill) { create(:skill) }

  def add_training(index)
    training = create(:training, skill: skill, name_en: "Progress training #{index}")
    session = create(:training_session, training: training, level: "Beginner")
    create(:certification, user: user, training: training, training_session: session, level: "Beginner")
    awarded = create(:proficient_project, training: training, level: "Beginner")
    create(:proficient_project, training: training, level: "Intermediate")
    create(:order_item, :awarded, proficient_project: awarded, order: create(:order, :completed, user: user))
    done = create(:learning_module, training: training, level: "Beginner")
    create(:learning_module, training: training, level: "Intermediate")
    create(:learning_module_track, :completed, user: user, learning_module: done)
  end

  def progress_queries
    queries = []
    callback = lambda do |*, payload|
      queries << payload[:sql] if payload[:sql].match?(PROGRESS_TABLES) && payload[:name] != "SCHEMA"
    end
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { yield }
    queries.size
  end

  def page_queries(path)
    content_login!(user)
    get path
    expect(response).to have_http_status(:ok)
    progress_queries { get path }
  end

  { "the profile page" => -> { user_path(user.username) },
    "the volunteer stats page" => -> { my_stats_volunteers_path } }.each do |label, path|
    it "queries training progress on #{label} the same number of times for one training or four" do
      add_training(1)
      one = page_queries(instance_exec(&path))
      3.times { |i| add_training(i + 2) }
      four = page_queries(instance_exec(&path))

      expect(four).to eq(one)
    end
  end

  it "shows each training's awarded projects, completed modules and recommended hours on the profile page" do
    add_training(1)
    content_login!(user)

    get user_path(user.username)

    expect(response.body).to include("Proficient projects awarded: 1")
    expect(response.body).to include("Learning modules completed: 1")
    expect(response.body).to include("Recommended hours before moving on: 2")
  end
end

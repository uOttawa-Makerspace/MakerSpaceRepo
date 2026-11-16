# frozen_string_literal: true

require "rails_helper"

# The certifications tab lists the highest certification of each training with its training,
# trainer and session; with Bullet raising under CI=1 a profile with several trainings that loads
# these one certification at a time fails.
RSpec.describe "Profile certifications tab", type: :request do
  include ContentSpecHelpers

  let(:admin) { create(:user, :admin) }
  let(:learner) { create(:user, :regular_user) }

  def certify(training, level)
    session = create(:training_session, training: training, level: level, user: create(:user, :staff))
    Certification.create!(user: learner, training_session: session, level: level)
  end

  it "lists the highest certification of each of several trainings without a query per certification" do
    trainings = Array.new(3) { |i| create(:training, name_en: "Certified training #{i}") }
    certify(trainings[0], "Beginner")
    certify(trainings[0], "Advanced")
    certify(trainings[1], "Beginner")
    certify(trainings[1], "Intermediate")
    certify(trainings[2], "Beginner")
    content_login!(admin)

    get user_path(learner.username)

    expect(response).to have_http_status(:ok)
    expect(response.body.scan("Demote").size).to eq(3)
    expect(Certification.highest_certifications(learner.id).map(&:level)).to contain_exactly("Advanced", "Intermediate", "Beginner")
  end

  def certify_through_project(training, level)
    project = create(:proficient_project, training: training)
    cert = Certification.create!(user: learner, level: level)
    create(:proficient_project_session, certification: cert, proficient_project: project, user: create(:user, :staff), level: level)
  end

  def queries_reading_the_list
    queries = 0
    counter = ->(*, payload) { queries += 1 unless payload[:name] == "SCHEMA" || payload[:cached] }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
      Certification.highest_certifications(learner.id).each do |cert|
        cert.training.localized_name
        cert.trainer.name
        cert.training_session
      end
    end
    queries
  end

  it "loads the trainings and trainers of all listed certifications in a fixed number of queries" do
    certify(create(:training), "Beginner")
    certify_through_project(create(:training), "Beginner")
    two = queries_reading_the_list

    2.times { certify(create(:training), "Intermediate") }
    certify_through_project(create(:training), "Advanced")

    expect(Certification.highest_certifications(learner.id).size).to eq(5)
    expect(queries_reading_the_list).to eq(two)
  end
end

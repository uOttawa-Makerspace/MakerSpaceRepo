# frozen_string_literal: true

require "rails_helper"

# The home page's badge card and /development_programs/all_badges show each of the user's badges with its training's
# name and skill colour. A badge's training comes through its training session, or through the proficient project for
# a badge earned there. The trainings are loaded once for the whole list, so the number of queries does not grow with
# the number of badges. The counts start at two badges: with one, the query cache can hide a repeated read.
RSpec.describe "Badge lists: queries", type: :request do
  let(:member) { create(:user, :regular_user) }
  let(:skill_colours) { { 1 => "#488b2c", 2 => "#dc4720" } }

  # One badge from a training session and one from a proficient project per pair, each with its own training.
  def add_badges(pairs)
    pairs.times.flat_map do
      [session_badge(create(:training)), project_badge(create(:training))]
    end
  end

  def session_badge(training)
    session = create(:training_session, training: training, level: "Beginner", user: create(:user, :staff))
    Certification.create!(user: member, training_session: session, level: "Beginner")
  end

  def project_badge(training)
    cert = Certification.create!(user: member, level: "Intermediate")
    create(:proficient_project_session, certification: cert, proficient_project: create(:proficient_project, training: training),
                                        user: create(:user, :staff), level: "Intermediate")
    cert
  end

  def queries_for(path)
    get path
    count_queries { get path }
  end

  # Each badge link with the badge's name and the colour of its skill.
  def badges(scope)
    Nokogiri::HTML(response.body).css("#{scope} a[href^='/badges/']").map do |link|
      [link["href"], link.at_css("svg title").text, link.at_css("svg g")["fill"]]
    end
  end

  def expected(certs)
    certs.map do |cert|
      training = cert.training_session&.training || cert.proficient_project_session.proficient_project.training
      [badge_path(cert.share_token), training.localized_name, skill_colours.fetch(training.skill_id, "#3f7ed1")]
    end
  end

  before { log_in!(member) }

  describe "home page badge card" do
    it "shows each badge with its training's name and skill colour" do
      certs = add_badges(1)
      get root_path

      expect(response).to have_http_status(:ok)
      expect(badges(".home-card")).to match_array(expected(certs))
    end

    it "runs the same number of queries for two badges as for five" do
      add_badges(1)
      two = queries_for(root_path)
      certs = add_badges(1) + [session_badge(create(:training))]
      five = queries_for(root_path)

      expect(badges(".home-card").size).to eq(5)
      expect(badges(".home-card")).to include(*expected(certs))
      expect(five).to eq(two)
    end
  end

  describe "all badges page" do
    it "shows each badge under its skill with its training's name and skill colour" do
      certs = add_badges(1)
      get all_badges_development_programs_path

      expect(response).to have_http_status(:ok)
      expect(badges("section")).to match_array(expected(certs))
    end

    it "runs the same number of queries for two badges as for five" do
      add_badges(1)
      two = queries_for(all_badges_development_programs_path)
      add_badges(1)
      session_badge(create(:training))
      five = queries_for(all_badges_development_programs_path)

      expect(badges("section").size).to eq(5)
      expect(five).to eq(two)
    end
  end
end

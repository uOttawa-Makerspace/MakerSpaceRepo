# frozen_string_literal: true

require "rails_helper"

# The profile badges tab shows a badge for every active certification whose training has badges, linked by the
# certification's share token. The trainings behind the badges are loaded together, not one query per certificate.
RSpec.describe "Profile badges tab", type: :request do
  include ContentSpecHelpers

  let(:user) { create(:user, :regular_user) }

  def certify(training, level)
    session = create(:training_session, training: training, level: level, user: create(:user, :staff))
    Certification.create!(user: user, training_session: session, level: level)
  end

  def certify_through_project(training, level)
    project = create(:proficient_project, training: training)
    cert = Certification.create!(user: user, level: level)
    create(:proficient_project_session, certification: cert, proficient_project: project, user: create(:user, :staff), level: level)
    cert
  end

  def badge_tab
    Nokogiri::HTML(response.body).at_css("#badges-manager")
  end

  def badge_links
    badge_tab.css("a[target=_blank]").map { |link| [link["href"], link.at_css("title").text, link.css("tspan").map { |t| t.text.strip }.last] }
  end

  def add_badges
    laser = create(:training, name_en: "Laser", skill: create(:skill))
    print = create(:training, name_en: "Print", skill: create(:skill))
    plain = create(:training, name_en: "Plain", has_badge: false)
    certs = [certify(laser, "Beginner"), certify(print, "Advanced"), certify_through_project(laser, "Intermediate")]
    certify(plain, "Beginner")
    certs
  end

  before { content_login!(user) }

  it "lists a linked badge for each active certification whose training has badges" do
    laser, print, project = add_badges
    certify(create(:training, name_en: "Removed"), "Beginner").deactivate(create(:user, :staff))

    get user_path(user.username)

    expect(badge_links).to contain_exactly(
      [badge_path(laser.badge_param), "Laser", "I"],
      [badge_path(print.badge_param), "Print", "III"],
      [badge_path(project.badge_param), "Laser", "II"]
    )
  end

  it "says so when the user has no badges" do
    get user_path(user.username)

    expect(badge_tab.text.squish).to include("You don't have any badges.")
  end

  it "loads the trainings of all the certificates in a fixed number of queries" do
    add_badges
    get user_path(user.username)
    few = count_queries { get user_path(user.username) }
    3.times { |i| certify(create(:training, name_en: "More #{i}"), "Beginner") }
    certify_through_project(create(:training), "Beginner")
    many = count_queries { get user_path(user.username) }

    expect(many).to eq(few)
  end
end

# frozen_string_literal: true

require "rails_helper"

# A profile lists the user's repositories (or makes) as cards with their first photo, their badges and, for an admin,
# their membership history. The photos, badge trainings and membership tiers are loaded once for the whole page, so
# the number of queries does not grow with the number of repositories, badges or memberships. The counts start at two
# rows: with a single row, two lists of the same one training read it with the same query, and the second is cached.
RSpec.describe "Profile page queries", type: :request do
  let(:member) { create(:user, :regular_user) }
  let(:skill) { create(:skill) }

  def add_rows(count)
    count.times do |i|
      create(:repository, owner: member, users: [member], title: "Repo #{Repository.count}")
      create(:repository, owner: member, users: [member], make_id: Repository.first.id, title: "Make #{Repository.count}")
      training = create(:training, skill: skill, has_badge: true)
      create(:learning_module, training: training)
      session = create(:training_session, training: training, level: "Beginner", user: create(:user, :staff))
      Certification.create!(user: member, training_session: session, level: "Beginner")
      create(:membership, user: member, status: i.even? ? "paid" : "revoked")
    end
  end

  def queries_for(path)
    get path
    count_queries { get path }
  end

  def cards = Nokogiri::HTML(response.body).css(".card.h-100")

  it "shows each repository card with its first photo" do
    sign_in_as(:regular)
    repo = create(:repository, owner: member, users: [member], title: "Two photos")
    repo.photos.create!(image: FilesTestHelper.png)
    create(:repository, owner: member, users: [member], title: "No photo").photos.destroy_all

    get user_path(member.username)

    shown = cards.to_h { |card| [card.at_css(".card-body p").text, card.at_css("img")["src"]] }
    expect(shown["Two photos"]).to include("/rails/active_storage/representations/").and include("avatar.png")
    expect(shown["No photo"]).to include("C_square")
  end

  it "shows an admin the member's membership history with each tier's title" do
    sign_in_as(:admin)
    tier = create(:membership_tier, title_en: "Gold Membership")
    create(:membership, user: member, membership_tier: tier, status: "paid")

    get user_path(member.username)

    rows = Nokogiri::HTML(response.body).css("#admin-membership tbody tr td:first-child").map { |td| td.text.squish }
    expect(rows).to eq(["Gold"])
  end

  %i[guest regular admin].each do |role|
    it "runs the same number of queries for two repositories, badges and memberships as for five, for a #{role}" do
      sign_in_as(role)
      add_rows(2)
      two = queries_for(user_path(member.username))
      add_rows(3)
      five = queries_for(user_path(member.username))

      expect(response).to have_http_status(:ok)
      expect(cards.size).to eq(5)
      expect(five).to eq(two)
    end
  end

  it "runs the same number of queries for two makes as for five" do
    add_rows(2)
    two = queries_for(user_path(member.username, show: "makes"))
    add_rows(3)
    five = queries_for(user_path(member.username, show: "makes"))

    expect(response).to have_http_status(:ok)
    expect(cards.size).to eq(5)
    expect(five).to eq(two)
  end
end

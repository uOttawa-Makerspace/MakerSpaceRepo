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

  describe "joined projects tab" do
    let(:path) { user_path(member.username, show: "projects_assigned") }

    # Each joined proposal has its own author, so no read of one is answered from the query cache.
    def join_proposals!(count)
      Array.new(count) do
        create(:project_proposal, user: create(:user, :regular_user)).tap do |proposal|
          ProjectJoin.create!(user: member, project_proposal: proposal)
        end
      end
    end

    def joined_rows
      Nokogiri::HTML(response.body).css(".repository-container").map do |row|
        [row.at_css(".title a").text, row.at_css(".title a")["href"], row.css(".start > div")[1].text.squish]
      end
    end

    it "shows each joined proposal with its link and author, or the deleted-user label without one" do
      with_author = join_proposals!(1).first
      orphan = create(:project_proposal, user: nil, title: "No author")
      ProjectJoin.create!(user: member, project_proposal: orphan)

      get path

      expect(response).to have_http_status(:ok)
      expect(joined_rows).to contain_exactly(
        [with_author.title, project_proposal_path(with_author), "by #{with_author.user.username}"],
        ["No author", project_proposal_path(orphan), "by [Deleted User]"]
      )
    end

    it "shows a joined proposal's first photo as its card background, and no background without a photo" do
      with_photo, without_photo = join_proposals!(2)
      with_photo.photos.attach(FilesTestHelper.png)

      get path

      expect(response).to have_http_status(:ok)
      backgrounds = Nokogiri::HTML(response.body).css(".repository-container").to_h do |row|
        [row.at_css(".title a").text, row.at_css(".repo-display-wrapper")["style"]]
      end
      expect(backgrounds[with_photo.title]).to include("/rails/active_storage/blobs/").and include("test.png")
      expect(backgrounds[without_photo.title]).to eq("background-image:url('')")
    end

    it "runs the same number of queries for two joined proposals with photos as for five" do
      join_proposals!(2).each { |proposal| proposal.photos.attach(FilesTestHelper.png) }
      two = queries_for(path)
      join_proposals!(3).each { |proposal| proposal.photos.attach(FilesTestHelper.png) }
      five = queries_for(path)

      expect(response).to have_http_status(:ok)
      expect(joined_rows.size).to eq(5)
      expect(five).to eq(two)
    end

    it "runs the same number of queries for two joined proposals as for five" do
      join_proposals!(2)
      two = queries_for(path)
      join_proposals!(3)
      five = queries_for(path)

      expect(response).to have_http_status(:ok)
      expect(joined_rows.size).to eq(5)
      expect(five).to eq(two)
    end
  end

  describe "repositories and makes tabs" do
    def join_rows_read(path)
      get path
      statements = []
      collect = ->(*, payload) { statements << payload[:sql] unless payload[:cached] }
      ActiveSupport::Notifications.subscribed(collect, "sql.active_record") { get path }
      statements.grep(/\ASELECT "project_joins"\.\* FROM "project_joins"/)
    end

    def card_row_count = Nokogiri::HTML(response.body).css("section.mb-3 > div.row").size

    it "reads no project join rows on the tabs that do not list them" do
      create(:repository, owner: member, users: [member], title: "Shown")
      ProjectJoin.create!(user: member, project_proposal: create(:project_proposal))

      [user_path(member.username), user_path(member.username, show: "repositories"),
       user_path(member.username, show: "makes")].each do |path|
        expect(join_rows_read(path)).to be_empty, path
      end
      expect(cards.size).to eq(0)
      get user_path(member.username)
      expect(cards.map { |card| card.at_css(".card-body p").text }).to eq(["Shown"])
    end

    it "draws the card row unless both the list and the joined projects are empty" do
      sign_in_as(:regular)
      get user_path(member.username)
      expect(card_row_count).to eq(0)

      ProjectJoin.create!(user: member, project_proposal: create(:project_proposal))
      get user_path(member.username)
      expect([card_row_count, cards.size]).to eq([1, 0])

      ProjectJoin.where(user: member).delete_all
      create(:repository, owner: member, users: [member], title: "Shown")
      get user_path(member.username)
      expect([card_row_count, cards.size]).to eq([1, 1])
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

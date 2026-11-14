# frozen_string_literal: true

require "rails_helper"

# The explore page, a project proposal's linked repositories and a user's liked repositories share the same
# sort options: newest first by default (also for an unknown or malformed sort), most likes, most makes, or
# most recently updated.
RSpec.describe "Repository sort order", type: :request do
  let(:owner) { create(:user, :regular_user) }
  let(:proposal) { create(:project_proposal, :approved, user: owner) }

  around { |example| travel_to(Time.zone.local(2026, 11, 14, 12)) { example.run } }

  let!(:repos) do
    {
      "Oldest Liked" => { like: 9, make: 1, created_at: 3.days.ago, updated_at: 3.days.ago },
      "Middle Made" => { like: 1, make: 9, created_at: 2.days.ago, updated_at: 2.days.ago },
      "Newest Plain" => { like: 0, make: 0, created_at: 1.day.ago, updated_at: 4.days.ago }
    }.map do |title, attrs|
      repo = create(:repository, owner: owner, title: title, share_type: "public", project_proposal_id: proposal.id)
      repo.tap { |r| r.update_columns(attrs) }
    end
  end

  def titles_in_order(body)
    repos.map(&:title).sort_by { |title| body.index(title) || raise("#{title} not listed") }
  end

  EXPECTED = {
    nil => ["Newest Plain", "Middle Made", "Oldest Liked"],
    "newest" => ["Newest Plain", "Middle Made", "Oldest Liked"],
    "most_likes" => ["Oldest Liked", "Middle Made", "Newest Plain"],
    "most_makes" => ["Middle Made", "Oldest Liked", "Newest Plain"],
    "recently_updated" => ["Middle Made", "Oldest Liked", "Newest Plain"],
    "unknown" => ["Newest Plain", "Middle Made", "Oldest Liked"],
    ["most_likes"] => ["Newest Plain", "Middle Made", "Oldest Liked"]
  }.freeze

  {
    "explore page" => ->(params) { get explore_path, params: params },
    "project proposal page" => ->(params) { get project_proposal_path(proposal), params: params },
    "liked repositories page" => lambda do |params|
      repos.each { |repo| Like.create!(user_id: owner.id, repository_id: repo.id) }
      post login_authentication_path, params: { username_email: owner.username, password: "asa32A353#" }
      get likes_user_path(owner.username), params: params
    end
  }.each do |page, visit|
    describe page do
      EXPECTED.each do |sort, order|

        it "orders by #{sort.inspect}" do
          instance_exec(sort.nil? ? {} : { sort: sort }, &visit)

          expect(response).to have_http_status(:ok)
          expect(titles_in_order(response.body)).to eq(order)
        end
      end
    end
  end

  describe "liked repositories page sort label" do
    def sort_label
      Nokogiri::HTML(response.body).at_css("#sort-dropdown-menu").text.squish
    end

    before { post login_authentication_path, params: { username_email: owner.username, password: "asa32A353#" } }

    { "most_likes" => "Sort by Most Likes", "unknown" => "Sort by Newest", ["most_likes"] => "Sort by Newest" }
      .each do |sort, label|
        it "names the sort applied for #{sort.inspect}" do
          get likes_user_path(owner.username), params: { sort: sort }

          expect(response).to have_http_status(:ok)
          expect(sort_label).to eq(label)
        end
      end

    it "names no sort when none is chosen" do
      get likes_user_path(owner.username)

      expect(sort_label).to eq("Sort by")
    end
  end
end

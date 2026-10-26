# frozen_string_literal: true

require "rails_helper"

# Chunk 17: SearchController (explore, search, category, equipment) as seen by
# a guest. All actions are public. Repository.public_repos limits explore and
# search to share_type "public"; the owner's username is the only user data in
# a result card.
RSpec.describe "Search and explore", type: :request do
  let!(:pub_laser) { create(:repository, title: "Laser Cut Lamp", description: "A lamp") }
  let!(:pub_robot) { create(:repository, title: "Robot Arm", description: "Servo driven") }
  let!(:private_laser) { create(:repository, :private, title: "Laser Secret Prototype", description: "Hidden") }

  def repos
    controller.instance_variable_get(:@repositories).to_a
  end

  describe "GET /explore" do
    # N+1 pinned: see defects D-PERF-P01
    it "lists public repositories newest first and never private ones", skip_bullet: true do
      get explore_path
      expect(response).to have_http_status(:ok)
      expect(repos).to eq([pub_robot, pub_laser])
      expect(response.body).to include("Laser Cut Lamp")
      expect(response.body).not_to include("Laser Secret Prototype")
    end

    it "paginates by 12" do
      create_list(:repository, 12)
      get explore_path
      expect(repos.size).to eq(12)
      get explore_path(page: 2)
      expect(repos.size).to eq(2)
    end

    it "answers 200 with an empty page past the end" do
      get explore_path(page: 99)
      expect(response).to have_http_status(:ok)
    end

    it "filters by category slug and ignores unknown slugs" do
      CategoryOption.find_or_create_by!(name: "Wearable")
      Category.create!(repository_id: pub_robot.id, name: "Wearable")
      get explore_path(category: "wearable")
      expect(repos).to eq([pub_robot])
      # WART(D-P20): an unrecognised category slug resolves to a nil name, which matches repositories that have NO category at all
      get explore_path(category: "nonsense")
      expect(repos).to eq([pub_laser])
    end

    # N+1 pinned: see defects D-PERF-P01
    it "sorts by most_likes and ignores a hostile sort value", skip_bullet: true do
      pub_laser.update_columns(like: 5)
      get explore_path(sort: "most_likes")
      expect(repos.first).to eq(pub_laser)
      get explore_path(sort: "created_at; DROP TABLE repositories")
      expect(response).to have_http_status(:ok)
      expect(Repository.count).to eq(3)
    end
  end

  describe "GET /search" do
    it "matches by fuzzy title and renders the explore view" do
      get search_path(q: "Laser")
      expect(response).to have_http_status(:ok)
      expect(repos).to eq([pub_laser])
      expect(response.body).to include("Search results for Laser")
    end

    it "matches the description too" do
      get search_path(q: "Servo driven")
      expect(repos).to include(pub_robot)
    end

    # What a guest can learn about private repos: nothing (title, description or existence).
    it "never returns or leaks private repositories, by title or description" do
      get search_path(q: "Laser Secret Prototype")
      expect(repos).not_to include(private_laser)
      expect(response.body).not_to include("Hidden")
      get search_path(q: "Hidden")
      expect(repos).to be_empty
    end

    it "returns every public repository for an empty query" do
      get search_path(q: "")
      expect(response).to have_http_status(:ok)
      expect(repos).to match_array([pub_laser, pub_robot])
      get search_path
      expect(repos).to match_array([pub_laser, pub_robot])
    end

    it "returns nothing (200) for a query that matches nothing" do
      get search_path(q: "zzzzqqqq")
      expect(response).to have_http_status(:ok)
      expect(repos).to eq([])
    end

    it "treats SQL metacharacters and LIKE wildcards as plain text" do
      ["'; DROP TABLE repositories; --", "%", "_", "\\", "\" OR 1=1 --", "a" * 5000].each do |q|
        get search_path(q: q)
        expect(response).to have_http_status(:ok), q[0, 30].inspect
      end
      expect(Repository.count).to eq(3)
    end

    it "escapes markup in the echoed query (heading and title)" do
      get search_path(q: "<script>alert(1)</script>")
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("<script>alert(1)</script>")
      expect(response.body).to include("&lt;script&gt;alert(1)&lt;/script&gt;")
    end

    # WART(D-P21): a NUL byte, or an array/hash q param, reaches the SQL layer unvalidated and answers 500
    it "answers 500 for a NUL byte, array or hash q param" do
      get search_path(q: "\u0000x")
      expect(response).to have_http_status(:internal_server_error)
      get "/search?q[]=Laser"
      expect(response).to have_http_status(:internal_server_error)
      get "/search?q[a]=Laser"
      expect(response).to have_http_status(:internal_server_error)
    end

    it "filters by multiple categories" do
      CategoryOption.find_or_create_by!(name: "Wearable")
      CategoryOption.find_or_create_by!(name: "Virtual Reality")
      Category.create!(repository_id: pub_robot.id, name: "Wearable")
      Category.create!(repository_id: pub_laser.id, name: "Virtual Reality")
      get "/search?category[]=wearable&category[]=virtual-reality"
      expect(repos).to match_array([pub_robot, pub_laser])
      get "/search?category=wearable"
      expect(response).to have_http_status(:ok)
      expect(repos).to eq([pub_robot])
    end

    it "ignores the liked filter for a guest and applies it for a signed-in user" do
      get search_path(liked: "1")
      expect(repos).to match_array([pub_laser, pub_robot])
      user = sign_in_as(:regular)
      Like.create!(user_id: user.id, repository_id: pub_robot.id)
      get search_path(liked: "1")
      expect(repos).to eq([pub_robot])
    end
  end

  describe "GET /category/:slug and /equipment/:slug" do
    # FIXED(D-P22): both pages go through Repository.public_repos, like explore and search
    it "lists only public repos filed under a legacy category, never private ones", skip_bullet: true do
      pub_robot.update_columns(category: "Mobile")
      private_laser.update_columns(category: "Mobile")
      get category_path(slug: "mobile-development")
      expect(response).to have_http_status(:ok)
      expect(repos.map(&:title)).to eq(["Robot Arm"])
      expect(response.body).not_to include("Laser Secret Prototype")
      expect(session[:user_id]).to be_nil
    end

    it "lists only public repos filed under a new-style category, for a guest and a signed-in user" do
      CategoryOption.find_or_create_by!(name: "Wearable")
      Category.create!(repository_id: private_laser.id, name: "Wearable")
      Category.create!(repository_id: pub_robot.id, name: "Wearable")
      get category_path(slug: "wearable")
      expect(repos).to eq([pub_robot])
      sign_in_as(:regular)
      get category_path(slug: "wearable")
      expect(repos).to eq([pub_robot])
    end

    it "a private repo's own owner and admin do not see it on the public category page either" do
      CategoryOption.find_or_create_by!(name: "Wearable")
      Category.create!(repository_id: private_laser.id, name: "Wearable")
      sign_in_as(:admin)
      get category_path(slug: "wearable")
      expect(repos).to be_empty
    end

    # N+1 pinned: see defects D-PERF-P01
    it "lists only public repos using a given equipment name", skip_bullet: true do
      Equipment.create!(repository_id: pub_robot.id, name: "3d printer")
      Equipment.create!(repository_id: private_laser.id, name: "3d printer")
      get equipment_path(slug: "3d-printer")
      expect(response).to have_http_status(:ok)
      expect(repos.map(&:title)).to eq(["Robot Arm"])
      expect(response.body).not_to include("Laser Secret Prototype")
    end

    it "hides soft-deleted repositories everywhere (Repository default_scope)" do
      pub_robot.update_columns(deleted: true, category: "Mobile")
      get explore_path
      expect(repos).not_to include(pub_robot)
      get search_path(q: "Robot")
      expect(repos).to be_empty
      get category_path(slug: "mobile-development")
      expect(repos).to be_empty
    end

    it "returns an empty page for an unknown slug" do
      get category_path(slug: "nope")
      expect(response).to have_http_status(:ok)
      expect(repos).to eq([])
      get equipment_path(slug: "nope")
      expect(repos).to eq([])
    end

    it "404s for the routed-but-missing likes and featured actions" do
      get likes_path
      expect(response).to have_http_status(:not_found)
      get featured_path(slug: "wearable")
      expect(response).to have_http_status(:not_found)
    end
  end
end

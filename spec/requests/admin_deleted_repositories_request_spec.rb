# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin deleted repositories", type: :request do
  include ContentSpecHelpers

  let(:owner) { create(:user, :regular_user) }
  let!(:repo) { create(:repository, owner: owner, title: "Gone Soon", users: [owner]) }

  before { repo.hide!(by: repo.owner) }

  describe "access" do
    it "sends a guest to sign in and restores nothing" do
      post admin_deleted_repository_restoration_path(repo.id)
      expect(response).to have_http_status(:found)
      expect(Repository.unscoped.find(repo.id).deleted).to be(true)
    end

    %i[regular staff].each do |role|
      it "sends #{role} to the home page and restores nothing" do
        content_sign_in_as(role)
        get admin_deleted_repositories_path
        expect(response).to redirect_to("/")
        post admin_deleted_repository_restoration_path(repo.id)
        expect(response).to redirect_to("/")
        expect(Repository.unscoped.find(repo.id).deleted).to be(true)
      end
    end
  end

  describe "GET index" do
    it "lists the deleted repositories with their owner for an admin" do
      content_sign_in_as(:admin)
      get admin_deleted_repositories_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Gone Soon", owner.username)
      expect(response.body).not_to include("<th>Deleted</th>")
    end

    it "lists the most recently deleted first" do
      later = create(:repository, owner: owner, title: "Gone Later", users: [owner])
      later.hide!(by: owner)
      content_sign_in_as(:admin)
      get admin_deleted_repositories_path
      expect(response.body.index("Gone Later")).to be < response.body.index("Gone Soon")
    end

    it "says so when none has been deleted" do
      repo.restore!
      content_sign_in_as(:admin)
      get admin_deleted_repositories_path
      expect(response.body).to include("No repository has been deleted.")
    end

    it "shows a repository whose owner's account is deleted" do
      owner.update_columns(deleted: true)
      content_sign_in_as(:admin)
      get admin_deleted_repositories_path
      expect(response.body).to include("Gone Soon", "Deleted account")
    end
  end

  describe "POST restoration" do
    before { content_sign_in_as(:admin) }

    it "brings the repository back with its comments and likes, and its page opens again" do
      create(:comment, repository: repo)
      create(:like, repository: repo)
      post admin_deleted_repository_restoration_path(repo.id)
      expect(response).to redirect_to(repository_path(owner.username, repo.id))
      expect(flash[:notice]).to eq("Repository restored.")
      get repository_path(owner.username, repo.id)
      expect(response).to have_http_status(:ok)
      expect([repo.comments.count, repo.likes.count]).to eq([1, 1])
    end

    it "refuses when the owner's account is deleted and leaves it hidden" do
      owner.update_columns(deleted: true)
      post admin_deleted_repository_restoration_path(repo.id)
      expect(response).to redirect_to(admin_deleted_repositories_path)
      expect(flash[:alert]).to eq("The repository was not restored. The owner's account is deleted. Restore the account to bring its repositories back.")
      expect(Repository.unscoped.find(repo.id).deleted).to be(true)
    end

    it "answers 404 for a repository that is not deleted" do
      visible = create(:repository, owner: owner, title: "Still Here")
      post admin_deleted_repository_restoration_path(visible.id)
      expect(response).to have_http_status(:not_found)
    end
  end
end

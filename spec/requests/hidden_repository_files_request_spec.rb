# frozen_string_literal: true

require "rails_helper"

# Active Storage serves any file to anyone who has its (permanent) URL, so deleting a repository
# has to stop its files from being served as well.
RSpec.describe "Files of a deleted repository", type: :request do
  include ContentSpecHelpers

  let(:owner) { create(:user, :regular_user) }
  let!(:repo) { create(:repository, owner: owner, title: "Files Inside", users: [owner]) }
  let!(:repo_file) { create(:repo_file, repository: repo) }
  let(:photo_blob) { repo.photos.first.image.blob }
  let(:file_blob) { repo.repo_files.first.file.blob }

  def served_paths(repository)
    photo = repository.photos.first.image
    file = repository.repo_files.reload.first.file
    {
      "photo proxy" => rails_storage_proxy_path(photo),
      "photo redirect" => rails_storage_redirect_path(photo),
      "photo variant proxy" => rails_storage_proxy_path(photo.variant(:explore)),
      "photo variant redirect" => rails_storage_redirect_path(photo.variant(:explore)),
      "file proxy" => rails_storage_proxy_path(file),
      "file redirect" => rails_storage_redirect_path(file),
      "photo short blob url" => "/rails/active_storage/blobs/#{photo.blob.signed_id}/#{photo.filename}",
      "photo disk" => URI(photo.blob.url(expires_in: 5.minutes)).path,
      "photo variant disk" => URI(photo.variant(:explore).processed.url(expires_in: 5.minutes)).path
    }
  end

  before { ActiveStorage::Current.url_options = { protocol: "http://", host: "www.example.com" } }

  context "while the repository is visible" do
    it "serves every route to a guest" do
      served_paths(repo).each do |name, path|
        get path
        expect(response.status).to be_in([200, 302, 206]), "#{name}: #{response.status}"
      end
    end
  end

  context "once the repository is deleted" do
    let!(:paths) { served_paths(repo).tap { repo.hide! } }

    it "answers 404 on every route to a guest" do
      paths.each do |name, path|
        get path
        expect(response).to have_http_status(:not_found), name
      end
    end

    it "answers 404 to a signed-in user who is not an admin, the owner included" do
      content_login!(owner)
      paths.each do |name, path|
        get path
        expect(response).to have_http_status(:not_found), name
      end
    end

    it "still serves an admin, without letting a shared cache keep the file" do
      content_sign_in_as(:admin)
      paths.each do |name, path|
        get path
        expect(response.status).to be_in([200, 302, 206]), "#{name}: #{response.status}"
      end
      get paths["photo proxy"]
      expect(response.headers["Cache-Control"]).to include("private").and include("no-store")
    end

    it "serves the files again once the repository is restored" do
      repo.restore!
      get paths["photo proxy"]
      expect(response).to have_http_status(:ok)
    end
  end

  it "keeps serving a file that is also attached to something visible" do
    other = create(:repository, owner: owner, title: "Shares The Photo", users: [owner])
    other.photos.first.image.attach(photo_blob)
    path = rails_storage_proxy_path(photo_blob)
    repo.hide!
    get path
    expect(response).to have_http_status(:ok)
  end

  it "keeps serving files that belong to other records (an avatar)" do
    user = create(:user, :regular_user)
    user.avatar.attach(io: File.open(Rails.root.join("spec/support/assets/avatar.png")), filename: "a.png", content_type: "image/png")
    repo.hide!
    get rails_storage_proxy_path(user.avatar)
    expect(response).to have_http_status(:ok)
  end

  describe "query cost" do
    def attachment_queries(&block)
      count = 0
      counter = ->(*, payload) { count += 1 if payload[:sql].include?('FROM "active_storage_attachments"') }
      ActiveSupport::Notifications.subscribed(counter, "sql.active_record", &block)
      count
    end

    it "asks for one set of attachments for an avatar" do
      user = create(:user, :regular_user)
      user.avatar.attach(io: File.open(Rails.root.join("spec/support/assets/avatar.png")), filename: "a.png", content_type: "image/png")
      path = rails_storage_proxy_path(user.avatar)
      expect(attachment_queries { get path }).to eq(1)
    end

    it "asks for at most two sets of attachments for the photo of a visible repository" do
      path = rails_storage_proxy_path(repo.photos.first.image)
      expect(attachment_queries { get path }).to be <= 2
    end
  end
end

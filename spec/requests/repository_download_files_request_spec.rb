# frozen_string_literal: true

require "rails_helper"

# Chunk 16: RepositoriesController#download_files (zip of repo_files).
#
# Gates: check_auth only (guests allowed for public repos). Zips are cached at
# tmp/repository_zips/makerepo_<id>.zip and re-used while newer than
# repository.updated_at; Repository#clear_zip_cache deletes it after_commit on
# update/destroy.
RSpec.describe "Repository zip download", type: :request do
  include ContentSpecHelpers

  let(:owner) { create(:user, :regular_user) }
  let!(:repo) { create(:repository, owner: owner, title: "Zip Me", users: [owner]) }

  def add_file(name, content: "data", type: "text/plain", repository: repo)
    RepoFile.create!(repository: repository, file: content_named_upload(name, content: content, type: type))
  end

  def zip_entries(body = response.body)
    entries = {}
    Zip::File.open_buffer(StringIO.new(body)) do |zip|
      zip.each { |e| entries[e.name] = e.get_input_stream.read }
    end
    entries
  end

  def download(r = repo, user_username: owner.username)
    get download_files_repositories_path(user_username, r.id)
  end

  after { FileUtils.rm_f(repo.zip_path) }

  it "redirects with an alert when the repository has no files" do
    download
    expect(response).to redirect_to(repository_path(owner.username, repo.slug))
    expect(flash[:alert]).to eq("This repository has no files to download.")
  end

  # N+1 pinned: see defects D-PERF-C01
  it "serves a zip of every file to a guest for a public repository", skip_bullet: true do
    add_file("a.txt", content: "AAA")
    add_file("b.txt", content: "BBB")
    download
    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("application/zip")
    expect(response.headers["Content-Disposition"]).to include("zip-me-#{repo.id}.zip")
    expect(zip_entries).to eq("a.txt" => "AAA", "b.txt" => "BBB")
  end

  # N+1 pinned: see defects D-PERF-C01
  it "prefixes the index to a duplicate file name", skip_bullet: true do
    add_file("same.txt", content: "one")
    add_file("same.txt", content: "two")
    download
    expect(zip_entries.keys).to contain_exactly("same.txt", "1_same.txt")
  end

  it "sanitizes path-traversal file names to a flat entry name (ActiveStorage::Filename)" do
    add_file("../../evil.txt", content: "x")
    download
    names = zip_entries.keys
    expect(names.size).to eq(1)
    expect(names.first).not_to include("/")
    expect(names.first).to end_with("evil.txt")
  end

  it "zips a legacy non-allow-listed file that predates the type validation (D-C06 now blocks new ones)" do
    legacy = RepoFile.new(repository: repo, file: content_named_upload("run.exe", content: "MZ", type: "application/x-msdownload"))
    legacy.save!(validate: false)
    download
    expect(zip_entries.keys).to eq(["run.exe"])
  end

  it "falls back to 'repository' in the file name when the title parameterizes to blank" do
    repo.update_columns(title: "$$$")
    add_file("a.txt")
    download
    expect(response.headers["Content-Disposition"]).to include("repository-#{repo.id}.zip")
  end

  it "re-uses the cached zip while it is newer than updated_at and rebuilds after an update" do
    add_file("a.txt", content: "v1")
    download
    expect(File.exist?(repo.zip_path)).to be(true)
    # stale content planted in the cache is served as-is while the cache is fresh
    FileUtils.touch(repo.zip_path, mtime: Time.now + 60)
    Zip::File.open(repo.zip_path) { |z| z.get_output_stream("planted.txt") { |f| f.write("cached") } }
    FileUtils.touch(repo.zip_path, mtime: Time.now + 60)
    download
    expect(zip_entries.keys).to include("planted.txt")
    # an update fires after_commit -> clear_zip_cache
    repo.update!(description: "changed")
    expect(File.exist?(repo.zip_path)).to be(false)
    download
    expect(zip_entries.keys).to eq(["a.txt"])
  end

  it "adding a RepoFile touches the repository, which invalidates the cache" do
    add_file("a.txt")
    download
    expect(File.exist?(repo.zip_path)).to be(true)
    add_file("b.txt")
    expect(File.exist?(repo.zip_path)).to be(false)
  end

  it "alerts and sends no zip when every blob is missing from storage" do
    rf = add_file("a.txt")
    rf.file.blob.service.delete(rf.file.blob.key)
    download
    expect(response).to redirect_to(repository_path(owner.username, repo.slug))
    expect(flash[:alert]).to eq("None of the files for this repository could be found in storage.")
    expect(File.exist?(repo.zip_path)).to be(false)
  end

  # N+1 pinned: see defects D-PERF-C01
  it "skips missing blobs but zips the rest", skip_bullet: true do
    gone = add_file("gone.txt")
    add_file("kept.txt", content: "K")
    gone.file.blob.service.delete(gone.file.blob.key)
    download
    expect(zip_entries).to eq("kept.txt" => "K")
  end

  it "ignores the username segment of the URL" do
    add_file("a.txt")
    download(user_username: "someone-else")
    expect(response).to have_http_status(:ok)
  end

  it "404s for an unknown or soft-deleted repository" do
    add_file("a.txt")
    repo.update_columns(deleted: true)
    download
    expect(response).to have_http_status(:not_found)
  end

  describe "private repositories" do
    let!(:secret) { create(:repository, :private, owner: owner, title: "Hush", users: [owner]) }
    before { add_file("s.txt", content: "S", repository: secret) }

    it "redirects a guest and a stranger to the password page with 'Password required'" do
      download(secret)
      expect(response).to redirect_to(password_entry_repository_path(owner.username, secret.id))
      expect(flash[:alert]).to eq("Password required")
      content_sign_in_as(:regular)
      download(secret)
      expect(response).to redirect_to(password_entry_repository_path(owner.username, secret.id))
    end

    it "serves the zip to the owner, staff and admin" do
      content_login!(owner)
      download(secret)
      expect(response).to have_http_status(:ok)
      expect(zip_entries.keys).to eq(["s.txt"])
    end

    %i[staff admin].each do |role|
      it "serves the zip to #{role}" do
        content_sign_in_as(role)
        download(secret)
        expect(response).to have_http_status(:ok)
      end
    end

    it "serves the zip after the password was passed for the numeric id" do
      secret.update_columns(password: BCrypt::Password.create("pw"))
      content_sign_in_as(:regular)
      post pass_authenticate_repository_path(owner.username, secret.id), params: { password: "pw" }
      download(secret)
      expect(response).to have_http_status(:ok)
    end
  end
end

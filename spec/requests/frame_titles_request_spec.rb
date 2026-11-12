# frozen_string_literal: true

require "rails_helper"

# Every embedded frame carries a title, so screen readers announce what it holds.
RSpec.describe "Frame titles", type: :request do
  include ContentSpecHelpers

  def frame_titles
    Nokogiri::HTML(response.body).css("iframe").map { |f| f["title"] }
  end

  def attach_pdf(attachment)
    attachment.attach(io: File.open(Rails.root.join("spec/support/assets/RepoFile1.pdf")), filename: "RepoFile1.pdf", content_type: "application/pdf")
  end

  it "titles the calendar page frame" do
    get calendar_path
    expect(frame_titles).to eq(["Calendar of events at CEED facilities"])
  end

  it "titles the calendar page frame in French" do
    get calendar_path(locale: :fr)
    expect(frame_titles).to eq(["Calendrier des événements des installations du CEED"])
  end

  it "titles a repository's video with the repository's name" do
    owner = create(:user, :regular_user)
    repo = create(:repository, youtube_link: "https://www.youtube.com/watch?v=dQw4w9WgXcQ", owner: owner, title: "Laser <Lamp>", users: [owner])
    get repository_path(repo.user_username, repo.slug)
    expect(frame_titles).to eq(["Video: Laser <Lamp>"])
  end

  it "titles each key certification document with its name" do
    staff = create(:user, :staff)
    cert = create(:key_certification, user_id: staff.id)
    attach_pdf(cert.pdf_file_1)
    log_in!(staff)
    get key_certification_path(cert)
    expect(frame_titles).to eq([KeyCertification::FILE_NAMES.first.gsub("-", " ").humanize])
  end

  it "titles each key certification document on the admin key page with its name" do
    holder = create(:user, :staff)
    cert = create(:key_certification, user_id: holder.id)
    attach_pdf(cert.pdf_file_2)
    space = create(:space)
    create(:key_request, :status_waiting_for_approval, :all_questions_answered, user: holder, space: space, supervisor: create(:user, :admin))
    key = create(:key, :regular_key_type, user: holder, space: space)
    sign_in_as(:admin)
    get admin_key_path(key)
    expect(frame_titles).to eq([KeyCertification::FILE_NAMES.second.gsub("-", " ").humanize])
  end

  describe "proficient project" do
    let(:project) { create(:proficient_project, training: create(:training), description: "See https://wiki.makerepo.com/en/page") }

    before do
      create(:repo_file, proficient_project: project)
      sign_in_as(:admin)
    end

    it "titles the wiki frame with the project's name and each file frame with its file name" do
      get proficient_project_path(project)
      expect(frame_titles).to eq(["Wiki resource for #{project.title}", "RepoFile1.pdf"])
    end
  end
end

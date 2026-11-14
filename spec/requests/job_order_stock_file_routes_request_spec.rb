# frozen_string_literal: true

require "rails_helper"

# Job order files are served only through the order's file route, which checks who is signed in. The stock Active
# Storage routes answer 404 for them, so a stock URL handed out before that route existed no longer serves the file.
# Every other stored file is served by the stock routes as before.
RSpec.describe "Job order files on the Active Storage routes", type: :request do
  include ContentSpecHelpers

  let(:owner) { create(:user, :regular_user) }
  let(:admin) { create(:user, :admin) }
  let(:order) { make_job_order!(owner: owner, status_key: :staff_approval) }
  let(:task) { order.job_tasks.create!(title: "Task #1") }
  let(:option) { JobOption.create!(name: "Paint", fee: 1, need_files: true) }

  before do
    seed_job_statuses!
    ActiveStorage::Current.url_options = { protocol: "http://", host: "www.example.com" }
    task.user_files.attach(FilesTestHelper.png)
  end

  def stock_paths(attachment)
    {
      "proxy" => rails_storage_proxy_path(attachment),
      "redirect" => rails_storage_redirect_path(attachment),
      "short blob url" => "/rails/active_storage/blobs/#{attachment.blob.signed_id}/#{attachment.filename}",
      "disk" => URI(attachment.blob.url(expires_in: 5.minutes)).path
    }
  end

  def image_paths(attachment)
    variant = attachment.variant(resize_to_limit: [10, 10])
    stock_paths(attachment).merge(
      "variant proxy" => rails_storage_proxy_path(variant),
      "variant redirect" => rails_storage_redirect_path(variant),
      "variant disk" => URI(variant.processed.url(expires_in: 5.minutes)).path
    )
  end

  def expect_refused(paths)
    paths.each do |name, path|
      get path
      expect(response).to have_http_status(:not_found), "#{name}: #{response.status}"
    end
  end

  def expect_served(paths)
    paths.each do |name, path|
      get path
      expect(response.status).to be_in([200, 302]), "#{name}: #{response.status}"
    end
  end

  describe "a job order file" do
    it "answers 404 to a guest on every stock route, the image variants included" do
      expect_refused(image_paths(task.user_files.first))
    end

    it "answers 404 to the order's owner and to an admin" do
      paths = image_paths(task.user_files.first)
      [owner, admin].each do |user|
        content_login!(user)
        expect_refused(paths)
      end
    end

    it "answers 404 for a staff file, an option file and a file attached to the order itself" do
      task.staff_files.attach(FilesTestHelper.stl)
      task.job_task_options.create!(job_option: option, option_file: FilesTestHelper.stl)
      order.staff_files.attach(FilesTestHelper.stl)

      [task.reload.staff_files.first, task.job_task_options.first.option_file_attachment, order.reload.staff_files.first]
        .each { |attachment| expect_refused(stock_paths(attachment)) }
    end

    it "is still sent to its owner through the order's file route" do
      attachment = task.user_files.first
      content_login!(owner)

      get job_order_file_path(order, attachment)
      expect(response).to have_http_status(:ok)
      expect(response.body).to eq(attachment.download)
    end
  end

  describe "other stored files" do
    it "serves an avatar to a guest" do
      user = create(:user, :regular_user)
      user.avatar.attach(FilesTestHelper.png)

      expect_served(image_paths(user.avatar.attachment))
    end

    it "serves a key certificate to a guest" do
      certification = KeyCertification.create!(user: owner)
      certification.pdf_file_1.attach(FilesTestHelper.pdf)

      expect_served(stock_paths(certification.pdf_file_1.attachment))
    end

    it "serves a visible repository's file to a guest" do
      repo = create(:repository, owner: owner, users: [owner])
      repo_file = create(:repo_file, repository: repo)

      expect_served(stock_paths(repo_file.file.attachment))
    end
  end
end

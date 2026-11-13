# frozen_string_literal: true

require "rails_helper"

# A job order's files are served by a MakerRepo route that checks the signed-in user may see the order: its owner,
# staff and admins. The order pages link to that route, never to an Active Storage URL.
RSpec.describe "Job order file downloads", type: :request do
  let(:owner) { create(:user, :regular_user) }
  let(:staff) { create(:user, :staff) }
  let(:admin) { create(:user, :admin) }
  let(:other) { create(:user, :regular_user) }
  let(:order) { make_job_order!(owner: owner, status_key: :staff_approval) }
  let(:task) { order.job_tasks.create!(title: "Task #1", job_type: JobType.find_by!(name: "3D Print")) }
  let(:option) do
    JobOption.create!(name: "Paint", fee: 1, need_files: true).tap { |o| o.job_types << JobType.find_by!(name: "3D Print") }
  end

  before do
    seed_job_statuses!
    seed_job_order_message!
    seed_job_types!
    task.user_files.attach(FilesTestHelper.stl)
    task.staff_files.attach(FilesTestHelper.stl)
    task.job_task_options.create!(job_option: option, option_file: FilesTestHelper.stl)
  end

  def task_attachments
    task.reload
    [task.user_files.first, task.staff_files.first, task.job_task_options.first.option_file_attachment]
  end

  def expect_download(attachment)
    get job_order_file_path(order, attachment)

    expect(response).to have_http_status(:ok)
    expect(response.headers["Content-Disposition"]).to start_with("attachment")
    expect(response.headers["Content-Disposition"]).to include(attachment.filename.to_s)
    expect(response.body).to eq(attachment.download)
  end

  describe "the order page" do
    it "links the client, option and staff files to the order's file route, not to Active Storage" do
      session_login!(owner)
      get job_order_path(order)

      expect(response).to have_http_status(:ok)
      task_attachments.each do |attachment|
        expect(response.body).to include(%(href="#{job_order_file_path(order, attachment)}"))
      end
      expect(response.body).not_to include("/rails/active_storage/")
    end
  end

  describe "the wizard" do
    it "links an uploaded client file to the order's file route" do
      session_login!(owner)
      get edit_job_order_job_task_path(order, task, step: 2)

      expect(response.body).to include(%(href="#{job_order_file_path(order, task_attachments.first)}"))
      expect(response.body).not_to include("/rails/active_storage/")
    end

    it "links an uploaded option file to the order's file route" do
      session_login!(owner)
      get edit_job_order_job_task_path(order, task, step: 3)

      expect(response.body).to include(%(href="#{job_order_file_path(order, task_attachments.last)}"))
      expect(response.body).not_to include("/rails/active_storage/")
    end
  end

  describe "GET /job_orders/:job_order_id/files/:id" do
    it "sends the owner each of the order's files" do
      session_login!(owner)
      task_attachments.each { |attachment| expect_download(attachment) }
    end

    it "sends staff each of the order's files" do
      session_login!(staff)
      task_attachments.each { |attachment| expect_download(attachment) }
    end

    it "sends an admin each of the order's files" do
      session_login!(admin)
      task_attachments.each { |attachment| expect_download(attachment) }
    end

    it "sends the owner a file attached to the order itself" do
      order.staff_files.attach(FilesTestHelper.stl)
      session_login!(owner)

      expect_download(order.reload.staff_files.first)
    end

    it "sends a guest to sign in" do
      get job_order_file_path(order, task_attachments.first)

      expect(response).to redirect_to(login_path(back_to: job_order_file_path(order, task_attachments.first)))
    end

    it "answers 404 to a signed-in user who may not see the order" do
      session_login!(other)
      task_attachments.each do |attachment|
        get job_order_file_path(order, attachment)
        expect(response).to have_http_status(:not_found)
      end
    end

    it "answers 404 for a file of another order, even to staff" do
      other_order = make_job_order!(owner: other, status_key: :staff_approval)
      other_task = other_order.job_tasks.create!(title: "Other")
      other_task.user_files.attach(FilesTestHelper.stl)
      session_login!(staff)

      get job_order_file_path(order, other_task.user_files.first)
      expect(response).to have_http_status(:not_found)
    end

    it "answers 404 for a file that belongs to something other than a job order" do
      session_login!(admin)
      admin.avatar.attach(FilesTestHelper.png)

      get job_order_file_path(order, admin.avatar.attachment)
      expect(response).to have_http_status(:not_found)
    end

    it "answers 404 for a deleted order" do
      attachment = task_attachments.first
      order.update!(is_deleted: true)
      session_login!(owner)

      get job_order_file_path(order, attachment)
      expect(response).to have_http_status(:not_found)
    end
  end
end

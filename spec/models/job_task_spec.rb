require "rails_helper"

RSpec.describe JobTask, type: :model do
  describe "Associations" do
    it { should belong_to(:job_order) }
    it { should belong_to(:job_type).optional }
    it { should belong_to(:job_service).optional }

    it { should have_many(:job_task_options).dependent(:destroy) }
    it { should have_many(:job_options).through(:job_task_options) }

    it { should accept_nested_attributes_for(:job_task_options).allow_destroy(true) }

    it { should have_one(:job_task_quote).dependent(:destroy) }
  end

  describe "Delegations" do
    it { should delegate_method(:user).to(:job_order) }
  end

  describe "ActiveStorage attachments" do
    it { should have_many_attached(:user_files) }
    it { should have_many_attached(:staff_files) }
  end

  describe "uploads" do
    include JobOrderSpecHelpers

    let(:order) { create(:job_order, user: create(:user, :regular_user)) }
    let(:task) { order.job_tasks.create!(title: "Task #1") }

    it "prefixes an attached user file's stored name with the order id (set_filename)" do
      task.user_files.attach(FilesTestHelper.stl)
      task.save!
      expect(task.reload.user_files.map { |f| f.filename.to_s }).to eq(["#{order.id}_test.stl"])
    end

    it "does not prefix the name twice on a later save" do
      task.user_files.attach(FilesTestHelper.stl)
      task.save!
      task.update!(title: "Task #1 renamed")
      expect(task.reload.user_files.first.filename.to_s).to eq("#{order.id}_test.stl")
    end

    it "rejects a user file of a disallowed content type" do
      task.user_files.attach(FilesTestHelper.mp4)
      expect(task).not_to be_valid
      expect(task.errors[:user_files].first).to start_with("file should be one of")
    end

    it "rejects a staff file of a disallowed content type" do
      task.staff_files.attach(FilesTestHelper.mp4)
      expect(task).not_to be_valid
      expect(task.errors[:staff_files].first).to start_with("file should be one of")
    end
  end

  describe "#user (delegated to the order)" do
    it "returns the order's owner" do
      owner = create(:user, :regular_user)
      task = create(:job_order, user: owner).job_tasks.create!(title: "Task #1")
      expect(task.user).to eq(owner)
    end
  end
end


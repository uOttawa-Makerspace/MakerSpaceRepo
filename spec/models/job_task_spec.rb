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
end

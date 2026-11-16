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

  describe "factory" do
    it "creates a task with no job type or service, which the task reports as missing information" do
      task = create(:job_task)
      expect(task).to be_persisted
      expect(task.job_type).to be_nil
      expect(task.job_service).to be_nil
      expect(task.missing_information?).to be(true)
    end

    # JobTasksController#create builds a task this way, so creating one never fails validation.
    it "is valid with only a title on its order, as the add-task button creates it" do
      order = create(:job_order)
      expect(order.job_tasks.build(title: "Task #1")).to be_valid
    end

    it "creates a task option on a created task" do
      expect(create(:job_task_option).job_task).to be_persisted
    end
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

    it "prefixes an attached user file's stored name with the order id" do
      task.user_files.attach(FilesTestHelper.stl)
      task.save!
      expect(task.reload.user_files.first.filename.to_s).to eq("test.stl")
      task.prefix_file_names
      expect(task.reload.user_files.map { |f| f.filename.to_s }).to eq(["#{order.id}_test.stl"])
    end

    it "prefixes a file whose name merely begins with the order id digits" do
      task.user_files.attach(FilesTestHelper.stl)
      task.save!
      task.user_files.first.blob.update!(filename: "#{order.id}abc.stl")
      task.prefix_file_names
      expect(task.reload.user_files.first.filename.to_s).to eq("#{order.id}_#{order.id}abc.stl")
    end

    it "does not prefix the name twice on a later save" do
      task.user_files.attach(FilesTestHelper.stl)
      task.save!
      task.prefix_file_names
      task.update!(title: "Task #1 renamed")
      task.prefix_file_names
      expect(task.reload.user_files.first.filename.to_s).to eq("#{order.id}_test.stl")
    end

    it "prefixes the stored name of an option file with JMTS, through the task, once" do
      option = task.job_task_options.create!(job_option: create(:job_option))
      option.option_file.attach(FilesTestHelper.png)
      option.reload
      expect(option.option_file.filename.to_s).to eq(FilesTestHelper.png_name)
      task.prefix_file_names
      task.prefix_file_names
      expect(option.reload.option_file.filename.to_s).to eq("JMTS_#{FilesTestHelper.png_name}")
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

  describe "#missing_information?" do
    let(:order) { create(:job_order) }
    let(:job_type) { create(:job_type) }

    it "is true without a job type" do
      expect(order.job_tasks.create!(title: "T")).to be_missing_information
    end

    it "is false for a job type that offers no services" do
      expect(order.job_tasks.create!(title: "T", job_type: job_type)).not_to be_missing_information
    end

    it "is true when the job type offers services and none is chosen" do
      group = create(:job_service_group, job_type: job_type)
      expect(order.job_tasks.create!(title: "T", job_type: job_type)).to be_missing_information
      service = create(:job_service, job_service_group: group)
      expect(order.job_tasks.create!(title: "T", job_type: job_type, job_service: service)).not_to be_missing_information
    end
  end

  describe "#service_price_missing?" do
    let(:order) { create(:job_order) }
    let(:job_type) { create(:job_type) }
    let(:service) { create(:job_service, job_service_group: create(:job_service_group, job_type: job_type)) }

    def task_with(service: nil, **quote)
      order.job_tasks.create!(title: "T", job_type: job_type, job_service: service).tap do |task|
        task.create_job_task_quote!(price: 1, **quote) if quote.any?
      end
    end

    it "is true for a job service with a blank price, or with no quote row" do
      expect(task_with(service: service, service_price: nil, service_quantity: 1)).to be_service_price_missing
      expect(task_with(service: service)).to be_service_price_missing
    end

    it "is false for a price of 0 (a free service) or any price" do
      expect(task_with(service: service, service_price: 0, service_quantity: 2)).not_to be_service_price_missing
      expect(task_with(service: service, service_price: 4, service_quantity: 2)).not_to be_service_price_missing
    end

    it "is false when the task has no job service, whatever the quantity (a new quote row defaults to 1)" do
      expect(task_with).not_to be_service_price_missing
      expect(task_with(service_price: nil, service_quantity: 1)).not_to be_service_price_missing
    end
  end
end

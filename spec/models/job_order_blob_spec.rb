# frozen_string_literal: true

require "rails_helper"

RSpec.describe JobOrderBlob do
  include JobOrderSpecHelpers

  let(:order) { make_job_order!(owner: create(:user, :regular_user)) }
  let(:task) { order.job_tasks.create!(title: "Task #1") }

  before { seed_job_statuses! }

  it "is true for a task file and for a file attached to the order itself" do
    task.user_files.attach(FilesTestHelper.png)
    order.staff_files.attach(FilesTestHelper.stl)

    expect(task.user_files.first.blob.job_order_file?).to be(true)
    expect(order.staff_files.first.blob.job_order_file?).to be(true)
  end

  it "is true for a legacy option row's file" do
    option = JobOption.create!(name: "Paint", fee: 1)
    row = order.job_order_options.create!(job_option: option)
    row.option_file.attach(FilesTestHelper.stl)

    expect(row.option_file.blob.job_order_file?).to be(true)
  end

  it "is false for a file attached to nothing of a job order" do
    user = create(:user, :regular_user)
    user.avatar.attach(FilesTestHelper.png)

    expect(user.avatar.blob.job_order_file?).to be(false)
  end

  it "is true for a variant of a task image and false for a variant of an avatar" do
    task.user_files.attach(FilesTestHelper.png)
    user = create(:user, :regular_user)
    user.avatar.attach(FilesTestHelper.png)

    variant_blob = ->(attachment) { attachment.variant(resize_to_limit: [10, 10]).processed.send(:record).image.blob }
    expect(variant_blob.call(task.user_files.first).job_order_file?).to be(true)
    expect(variant_blob.call(user.avatar.attachment).job_order_file?).to be(false)
  end

  it "is false for a variant whose record is gone" do
    task.user_files.attach(FilesTestHelper.png)
    blob = task.user_files.first.variant(resize_to_limit: [10, 10]).processed.send(:record).image.blob
    ActiveStorage::VariantRecord.delete_all

    expect(blob.job_order_file?).to be(false)
  end
end

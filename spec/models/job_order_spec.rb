require "rails_helper"

RSpec.describe JobOrder, type: :model do
  # The boot-time JobStatus constants resolve against a reference DB; seed the
  # migration-shipped rows and repoint the constants so model behavior matches
  # any deployed environment (same pattern as spec/support/job_orders_spec_helpers.rb).
  include JobOrderSpecHelpers

  describe "Association" do
    context "belongs_to" do
      it { should belong_to(:user).without_validating_presence }
    end

    context "belongs_to" do
      it { should have_many(:job_tasks).dependent(:destroy) }
      it { should have_many(:job_order_statuses) }
    end
  end

  describe "#total_price" do
    before { seed_job_types! }

    it "sums task quotes (price + service_price * service_quantity), quote options and line items" do
      order = create(:job_order, user: create(:user, :regular_user))
      priced_task = order.job_tasks.create!(title: "Task #1")
      priced_task.build_job_task_quote(price: 10, service_price: 3, service_quantity: 2).save!
      priced_task.reload.job_task_quote.job_task_quote_options
                 .create!(job_option: JobOption.create!(name: "Supports removal", fee: 2), price: 4)
      # A task WITHOUT a quote contributes nothing (skipped by the loop).
      order.job_tasks.create!(title: "Task #2")
      order.job_quote_line_items.create!(description: "Expedited SLA resin", price: 5)

      expect(order.reload.total_price).to eq(25.0)
    end

    it "is 0 for an order without any quotes" do
      order = create(:job_order, user: create(:user, :regular_user))
      order.job_tasks.create!(title: "Task #1")
      expect(order.total_price).to eq(0)
    end
  end

  describe "scope .without_drafts" do
    before { seed_job_statuses! }

    it "includes orders whose LATEST status row is not Draft" do
      submitted = create(:job_order, user: create(:user, :regular_user))
      travel(5.minutes) do
        submitted.job_order_statuses.create!(job_status: JobStatus::DRAFT, user: submitted.user)
      end
      travel(6.minutes) do
        submitted.job_order_statuses.create!(job_status: JobStatus::STAFF_APPROVAL, user: submitted.user)
      end

      expect(JobOrder.without_drafts).to include(submitted)
    end

    it "excludes orders whose latest status is Draft (decided by MAX(created_at), not by presence)" do
      draft_last = create(:job_order, user: create(:user, :regular_user))
      travel(5.minutes) do
        draft_last.job_order_statuses.create!(job_status: JobStatus::STAFF_APPROVAL, user: draft_last.user)
      end
      travel(6.minutes) do
        draft_last.job_order_statuses.create!(job_status: JobStatus::DRAFT, user: draft_last.user)
      end

      expect(JobOrder.without_drafts).not_to include(draft_last)
    end

    # WART(D-J22): without_drafts does not filter deleted rows — callers must compose
    # `.not_deleted` themselves (as JobOrdersController#admin does).
    it "keeps soft-deleted orders (deletion is a separate composition)" do
      submitted = create(:job_order, user: create(:user, :regular_user), is_deleted: true)
      travel(5.minutes) do
        submitted.job_order_statuses.create!(job_status: JobStatus::STAFF_APPROVAL, user: submitted.user)
      end
      expect(JobOrder.without_drafts).to include(submitted)
      expect(JobOrder.not_deleted.without_drafts).not_to include(submitted)
    end
  end

  describe "#allow_edit?" do
    before { seed_job_statuses! }

    it "allows editing in Draft and Staff-Pending states" do
      order = create(:job_order, user: create(:user, :regular_user))
      order.job_order_statuses.create!(job_status: JobStatus::DRAFT, user: order.user)
      expect(order.allow_edit?).to be(true)

      order.job_order_statuses.create!(job_status: JobStatus::STAFF_APPROVAL, user: order.user)
      expect(order.allow_edit?).to be(true)
    end

    it "locks editing once payment is waiting" do
      order = create(:job_order, user: create(:user, :regular_user))
      order.job_order_statuses.create!(job_status: JobStatus::COMPLETED, user: order.user)
      expect(order.allow_edit?).to be(false)
    end

    # WART(D-J20): allow_edit? has no nil guard on the status history
    it "crashes on an order with no status rows" do
      order = create(:job_order, user: create(:user, :regular_user))
      expect { order.allow_edit? }.to raise_error(NoMethodError)
    end
  end

  describe "#max_step" do
    it "is 1 until the order has a job type and an owner" do
      order = create(:job_order, user: nil)
      expect(order.max_step).to eq(1)
    end

    it "requires files to reach step 5" do
      owner = create(:user, :regular_user)
      seed_job_types!
      order = create(:job_order, user: owner)
      order.update!(job_type: JobType.find_by!(name: "3D Print"))
      expect(order.max_step).to eq(2)

      order.update!(user_files: [FilesTestHelper.stl])
      # No JobServiceGroups exist for the seeded job type => type alone qualifies.
      expect(order.reload.max_step).to eq(5)
    end
  end

  describe "#set_filename (after_save)" do
    it "prefixes stored user file blobs with the order id, twice-save safe" do
      order = create(:job_order, user: create(:user, :regular_user))
      order.update!(user_files: [FilesTestHelper.stl])

      blob = order.user_files.first
      expect(blob.filename.to_s).to eq("#{order.id}_test.stl")

      order.update!(comments: "again")
      expect(order.user_files.first.reload.filename.to_s).to eq("#{order.id}_test.stl")
    end

    it "prefixes staff files the same way" do
      order = create(:job_order, user: create(:user, :regular_user))
      order.update!(staff_files: [FilesTestHelper.stl])
      expect(order.staff_files.first.filename.to_s).to eq("#{order.id}_test.stl")
    end
  end

  describe "file content validations" do
    it "accepts STL (binary) and PNG uploads for user_files and staff_files" do
      order = build(:job_order, user: create(:user, :regular_user))
      order.user_files = [FilesTestHelper.stl, FilesTestHelper.png]
      expect(order).to be_valid
    end

    it "rejects other content types (mp4) with the shipped copy" do
      order = build(:job_order, user: create(:user, :regular_user))
      order.user_files = [FilesTestHelper.mp4]
      expect(order).not_to be_valid
      expect(order.errors[:user_files].first).to start_with("file should be one of")
    end
  end

  describe "scope .order_by_expedited" do
    # WART(D-J21): two stacked warts (dead code):
    #  1) the SQL interpolates `JobOption.find_by(name: "Expedited").id`
    #     without the reference row → nil dereference;
    #  2) even with the row, the scope joins the job_order_options association,
    #     whose backing model class was never shipped.
    it "raises NoMethodError on a missing 'Expedited' JobOption row" do
      expect(JobOption.find_by(name: "Expedited")).to be_nil
      expect { JobOrder.order_by_expedited.to_a }
        .to raise_error(NoMethodError, /undefined method 'id' for nil/)
    end

    # WART(D-J36): the has_many :job_order_options association has no model
    it "would still break: the joined association has no backing model class" do
      expect { create(:job_order).job_order_options.to_a }
        .to raise_error(NameError, /Missing model class JobOrderOption/)
    end
  end

  # Task-level expedition is a DIFFERENT mechanism (used by the submitted mail),
  # substring-matched on the option name.
  describe "#expedited?" do
    it "is true when any task option's name contains 'Expedited'" do
      order = create(:job_order, user: create(:user, :regular_user))
      task = order.job_tasks.create!(title: "Task #1")
      option = JobOption.create!(name: "Expedited Resin", fee: 2)
      task.job_task_options.create!(job_option: option)

      expect(order.reload.expedited?).to be(true)
    end

    it "is false otherwise" do
      order = create(:job_order, user: create(:user, :regular_user))
      order.job_tasks.create!(title: "Task #1")
      expect(order.reload.expedited?).to be(false)
    end
  end
end


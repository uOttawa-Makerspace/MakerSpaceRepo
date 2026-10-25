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

  describe "#total_price with nil prices" do
    before { seed_job_types! }

    it "treats a nil service_price / service_quantity as zero" do
      order = create(:job_order, user: create(:user, :regular_user))
      task = order.job_tasks.create!(title: "Task #1")
      task.build_job_task_quote(price: 10).save!

      expect(order.reload.total_price).to eq(10)
    end

    it "cannot hold a nil option price (validated), so the nil-safe `|| 0` branch is unreachable" do
      order = create(:job_order, user: create(:user, :regular_user))
      quote = order.job_tasks.create!(title: "Task #1").build_job_task_quote(price: 10).tap(&:save!)
      option = quote.job_task_quote_options.build(job_option: JobOption.create!(name: "Polish", fee: 1), price: nil)
      expect(option).not_to be_valid
      expect(option.errors[:price]).to eq(["is not a number"])
    end
  end

  # WART(D-J36): `has_many :job_order_options, dependent: :destroy` points at a
  # model that does not exist, so a real destroy (of an order, or of a user who
  # owns one) raises NameError while the controller only ever soft-deletes.
  describe "destroy" do
    it "JobOrder#destroy raises NameError (missing JobOrderOption) and keeps the row" do
      order = create(:job_order, user: create(:user, :regular_user))
      expect { order.destroy }.to raise_error(NameError, /Missing model class JobOrderOption/)
      expect(described_class.exists?(order.id)).to be(true)
    end

    it "User#destroy raises the same NameError for a user who owns an order, and keeps the user" do
      user = create(:user, :regular_user)
      create(:job_order, user: user)
      expect { user.destroy }.to raise_error(NameError, /Missing model class JobOrderOption/)
      expect(User.exists?(user.id)).to be(true)
    end

    it "User#destroy works for a user without job orders" do
      user = create(:user, :regular_user)
      expect { user.destroy }.not_to raise_error
      expect(User.exists?(user.id)).to be(false)
    end
  end

  describe "Shopify draft order helpers (GraphQL client stubbed at the boundary)" do
    before { seed_job_types! }

    let!(:shopify) { stub_shopify_admin!.tap { |fake| fake.invoice_url = "https://pay.example/inv-1" } }
    let(:order) { create(:job_order, user: create(:user, :regular_user)) }

    def quoted_task!(title, price:, service_price:, service_quantity:)
      order.job_tasks.create!(title: title).tap do |task|
        task.build_job_task_quote(price: price, service_price: service_price,
                                  service_quantity: service_quantity).save!
      end
    end

    describe "#shopify_draft_order_line_items" do
      it "builds a fee line per task, a parts line only when price and quantity are positive, option lines and a line-item total" do
        task = quoted_task!("Task #1", price: 20, service_price: 3, service_quantity: 2)
        task.job_task_quote.job_task_quote_options.create!(job_option: JobOption.create!(name: "Polish", fee: 1), price: 4)
        quoted_task!("Task #2", price: 5, service_price: 0, service_quantity: 0)
        order.job_quote_line_items.create!(description: "Rush", price: 2.5)

        lines = order.reload.send(:shopify_draft_order_line_items)
        expect(lines.map { |l| [l[:title], l[:originalUnitPriceWithCurrency][:amount]] }).to eq([
          ["Task #1 Service Fee", 20], ["Task #1 Parts Fee", 6], ["Task #1 Polish", 4],
          ["Task #2 Service Fee", 5], ["Line Items Total", BigDecimal("2.5")]
        ])
        expect(lines.map { |l| l[:quantity] }.uniq).to eq([1])
        expect(lines.map { |l| l[:originalUnitPriceWithCurrency][:currencyCode] }.uniq).to eq(["CAD"])
      end

      it "skips tasks without a quote" do
        order.job_tasks.create!(title: "Unquoted")
        expect(order.send(:shopify_draft_order_line_items).map { |l| l[:title] }).to eq(["Line Items Total"])
      end

      # WART(D-J49): the guards call .positive? on service_price / service_quantity
      # without a nil check, so a quote that never got a service price crashes.
      it "raises NoMethodError for a quote with a nil service_price" do
        order.job_tasks.create!(title: "Task #1").build_job_task_quote(price: 10).save!
        expect { order.reload.send(:shopify_draft_order_line_items) }
          .to raise_error(NoMethodError, /positive\?/)
      end
    end

    describe "#checkout_link" do
      it "creates the draft order once, stores its id and returns the invoice url" do
        quoted_task!("Task #1", price: 20, service_price: 0, service_quantity: 0)

        expect(order.reload.checkout_link).to eq("https://pay.example/inv-1")
        expect(order.shopify_draft_order_id).to eq("gid://shopify/DraftOrder/9001")
        expect(shopify.calls.map { |c| c[:query][/\b(draftOrderCreate|getDraftOrder)\b/] })
          .to eq(%w[draftOrderCreate getDraftOrder])
        created = shopify.calls.first[:variables][:input]
        expect(created[:tags]).to eq(["makerepo_test_job_order"])
        expect(created[:metafields]).to eq([{ namespace: "makerepo", key: "job_order_db_reference",
                                              value: order.id.to_s, type: "number_integer" }])
      end

      # WART(D-J38): after the first visit the draft order is only fetched, never
      # refreshed, so a later re-quote keeps the old Shopify line items.
      it "only fetches the existing draft order on later calls (no refresh of the line items)" do
        quoted_task!("Task #1", price: 20, service_price: 0, service_quantity: 0)
        order.reload.checkout_link
        shopify.calls.clear
        order.reload.job_tasks.first.job_task_quote.update!(price: 99)

        order.reload.checkout_link
        expect(shopify.calls.map { |c| c[:query][/\b(draftOrderCreate|getDraftOrder)\b/] }).to eq(%w[getDraftOrder])
      end

      it "raises a network error when Shopify answers with a non-200 while creating" do
        shopify.status = 502
        expect { order.checkout_link }.to raise_error(RuntimeError, /Network error: Received HTTP 502/)
      end

      it "raises when Shopify returns user errors" do
        shopify.user_errors = [{ "field" => "x", "message" => "Bad line item" }]
        expect { order.checkout_link }.to raise_error(RuntimeError, /Shopify Draft Order Creation Failed: Bad line item/)
      end
    end
  end
end

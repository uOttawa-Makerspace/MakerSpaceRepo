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

  describe "the latest status (the highest status row id)" do
    before { seed_job_statuses! }

    let(:owner) { create(:user, :regular_user) }
    # COMPLETED, then DRAFT: the latest is DRAFT (the highest id), however created_at and the array order say otherwise
    let(:order) do
      create(:job_order, user: owner).tap do |o|
        o.job_order_statuses.create!(job_status: JobStatus::COMPLETED, user: owner)
        o.job_order_statuses.create!(job_status: JobStatus::DRAFT, user: owner)
        o.job_order_statuses.order(:id).first.update_columns(created_at: 1.day.from_now)
      end
    end

    def preloaded_in_reverse(order)
      JobOrder.includes(:job_order_statuses).find(order.id).tap do |o|
        o.association(:job_order_statuses).target.reverse! # a preload in no particular order
      end
    end

    it "is the same for every reader, whatever order a preload came in" do
      loaded = preloaded_in_reverse(order)
      highest = order.job_order_statuses.reorder(id: :desc).first

      expect(loaded.job_order_statuses.map(&:id)).to eq([highest.id, highest.id - 1]) # not in id order
      expect(loaded.latest_status).to eq(highest)
      expect(loaded.latest_status.job_status_id).to eq(JobStatus::DRAFT.id)
      expect(loaded.latest_status.job_status_id).to eq(JobOrder.where(id: order.id).pick(Arel.sql(JobOrder::LATEST_STATUS_ID_SQL)))
      expect(loaded.allow_edit?).to be(true)
      expect(loaded.task_edits_offered_to?(owner)).to be(true)
      expect(order.reload.latest_status).to eq(highest) # unloaded: one query, the same row
    end

    it "has no latest_status_id reader (the SQL is the batch rule, #latest_status the instance rule)" do
      expect(order).not_to respond_to(:latest_status_id)
    end

    it "sorts a row built on a loaded association (no id yet) after the persisted ones, like .last, without raising" do
      loaded = JobOrder.includes(:job_order_statuses).find(order.id)
      built = loaded.job_order_statuses.build(job_status: JobStatus::STAFF_APPROVAL, user: owner)

      expect(loaded.job_order_statuses).to be_loaded
      expect { loaded.allow_edit? }.not_to raise_error
      expect(loaded.latest_status).to equal(built)
      expect(loaded.latest_status).to equal(loaded.job_order_statuses.last)
      expect(loaded.allow_edit?).to be(true) # STAFF_APPROVAL
      expect(loaded.job_order_statuses.build(job_status: JobStatus::COMPLETED, user: owner)).to equal(loaded.latest_status)
    end

    it "orders the association by id" do
      expect(JobOrder.includes(:job_order_statuses).find(order.id).job_order_statuses.map(&:id)).to eq(order.job_order_statuses.pluck(:id).sort)
    end

    it "is what .without_drafts decides on, when created_at and id disagree or tie" do
      expect(JobOrder.without_drafts).not_to include(order) # created_at says COMPLETED is latest, the id says DRAFT

      tied = create(:job_order, user: owner)
      now = Time.current.change(usec: 0)
      tied.job_order_statuses.create!(job_status: JobStatus::COMPLETED, user: owner, created_at: now)
      tied.job_order_statuses.create!(job_status: JobStatus::DRAFT, user: owner, created_at: now)
      expect(JobOrder.without_drafts).not_to include(tied)

      moved_on = create(:job_order, user: owner)
      moved_on.job_order_statuses.create!(job_status: JobStatus::DRAFT, user: owner, created_at: now)
      moved_on.job_order_statuses.create!(job_status: JobStatus::STAFF_APPROVAL, user: owner, created_at: now)
      expect(JobOrder.without_drafts).to include(moved_on)
      expect(JobOrder.without_drafts.where(id: moved_on.id).to_a).to eq([moved_on]) # one row per order
      expect(JobOrder.without_drafts).not_to include(create(:job_order, user: owner)) # no status at all
    end

    it "keeps checkout_link's fast path from serving a draft when the highest-id status is not COMPLETED" do
      shopify = stub_shopify_admin!
      loaded = preloaded_in_reverse(order) # COMPLETED is the LAST element of the array, DRAFT the highest id
      allow(loaded).to receive(:draft_order_current?).and_return(true)

      result = loaded.checkout_link

      expect(shopify.calls).to be_empty
      expect(result.value).to be_nil
    end
  end

  describe "scope .without_drafts" do
    it "is one correlated subquery comparison, and still excludes an order with no status" do
      sql = JobOrder.without_drafts.to_sql
      expect(sql.scan("SELECT s.job_status_id").size).to eq(1)
      expect(sql).not_to include("IS NOT NULL")
      expect(JobOrder.without_drafts.where(id: create(:job_order).id)).to be_empty
    end

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

    # D-J20, closed: JobOrder.editable_status? (also the delete rule) treats a missing status as not editable
    it "is false for an order with no status rows" do
      order = create(:job_order, user: create(:user, :regular_user))
      expect(order.allow_edit?).to be(false)
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

  # WART(D-J36): the has_many :job_order_options association has no model
  describe "job_order_options association" do
    it "has no backing model class" do
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
    # /pay only serves COMPLETED orders, and checkout_link re-checks that under the row lock (JOB-03)
    let(:order) { make_job_order!(owner: create(:user, :regular_user), status_key: :completed) }

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

      # FIXED(D-J49, with the D-J38 follow-up): nil service_price / quantity count as 0 (no parts line).
      it "treats a nil service_price as 0 (no parts fee line) instead of raising" do
        order.job_tasks.create!(title: "Task #1").build_job_task_quote(price: 10).save!
        titles = order.reload.shopify_draft_order_line_items.map { |l| l[:title] }
        expect(titles).to eq(["Task #1 Service Fee", "Line Items Total"])
      end
    end

    describe "#checkout_link" do
      it "creates the draft order once, stores its id and returns the invoice url" do
        quoted_task!("Task #1", price: 20, service_price: 0, service_quantity: 0)

        expect(order.reload.checkout_link.value).to eq("https://pay.example/inv-1")
        expect(order.shopify_draft_order_id).to eq("gid://shopify/DraftOrder/9001")
        expect(shopify.calls.map { |c| c[:query][/\b(draftOrderCreate|getDraftOrder)\b/] })
          .to eq(%w[draftOrderCreate getDraftOrder])
        created = shopify.calls.first[:variables][:input]
        expect(created[:tags]).to eq(["makerepo_test_job_order", "job_order:#{order.id}"])
        expect(created[:metafields]).to eq([{ namespace: "makerepo", key: "job_order_db_reference",
                                              value: order.id.to_s, type: "number_integer" }])
      end

      # FIXED(D-J38 / JOB-03): the draft remembers the line items it was built from. While they match it is only
      # fetched; once they change it is never served again (the order goes back to staff, see
      # spec/requests/job_orders_pay_fingerprint_request_spec.rb).
      it "stores a fingerprint with the id, then only fetches the draft while the line items still match" do
        quoted_task!("Task #1", price: 20, service_price: 0, service_quantity: 0)
        order.reload.checkout_link
        expect(order.reload.shopify_draft_order_fingerprint)
          .to eq(described_class.find(order.id).quote_fingerprint)
        shopify.calls.clear

        expect(order.reload.checkout_link.value).to eq("https://pay.example/inv-1")
        expect(shopify.calls.map { |c| c[:query][/\b(draftOrderCreate|getDraftOrder)\b/] }).to eq(%w[getDraftOrder])
      end

      it "does not serve the draft once the line items changed behind it" do
        quoted_task!("Task #1", price: 20, service_price: 0, service_quantity: 0)
        order.reload.checkout_link
        order.reload.job_tasks.first.job_task_quote.update!(price: 99)

        expect(order.reload.checkout_link.value).to be_nil
        expect(order.reload.shopify_draft_order_id).to be_nil
        expect(order.job_order_statuses.last.reason).to eq("invoice_mismatch")
      end

      it "fingerprints amounts by value at 2 decimals: 29.99 and 29.990 match, 29.98 does not" do
        quote = quoted_task!("Task #1", price: 29.99, service_price: 0, service_quantity: 0).job_task_quote
        before = described_class.find(order.id).quote_fingerprint
        quote.update!(price: BigDecimal("29.990"))
        expect(described_class.find(order.id).quote_fingerprint).to eq(before)
        quote.update!(price: 29.98)
        expect(described_class.find(order.id).quote_fingerprint).not_to eq(before)
        expect(described_class.money_string(nil)).to eq("0.00")
      end

      # Round 2 review 7: two plain includes-based snapshots, both dropped by reload
      it "reload drops both quote snapshots (total, fingerprint and draft lines all re-read)" do
        option = JobOption.create!(name: "Polish", fee: 1)
        quote = quoted_task!("Task #1", price: 10, service_price: 0, service_quantity: 0).job_task_quote
        quote.job_task_quote_options.create!(job_option: option, price: 3)
        order.reload
        fingerprint = order.quote_fingerprint
        expect(order.total_price).to eq(13)
        expect(order.shopify_draft_order_line_items.map { |l| l[:title] }).to include("Task #1 Polish")

        JobTaskQuote.where(id: quote.id).update_all(price: 20)
        JobOption.where(id: option.id).update_all(name: "Wax")
        expect(order.total_price).to eq(13) # memoized within the request

        order.reload
        expect(order.total_price).to eq(23)
        expect(order.quote_fingerprint).not_to eq(fingerprint)
        expect(order.shopify_draft_order_line_items.map { |l| l[:title] }).to include("Task #1 Wax")
      end

      # Round 3 review 6: ONE snapshot per request, so the total, the fingerprint and the draft lines cannot disagree
      it "loads the tasks once for the total, the fingerprint and the draft lines" do
        option = JobOption.create!(name: "Polish", fee: 1)
        quote = quoted_task!("Task #1", price: 10, service_price: 0, service_quantity: 0).job_task_quote
        quote.job_task_quote_options.create!(job_option: option, price: 3)
        order.reload

        task_loads = 0
        counter = lambda do |*, payload|
          task_loads += 1 if payload[:sql].match?(/\ASELECT\b.*FROM "job_tasks"/m)
        end
        ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
          order.total_price
          order.quote_fingerprint
          order.shopify_draft_order_line_items
          order.total_price
        end

        expect(task_loads).to eq(1)
      end

      it "does not fingerprint display titles: renaming a task or an option leaves it unchanged" do
        option = JobOption.create!(name: "Polish", fee: 1)
        quote = quoted_task!("Task #1", price: 10, service_price: 0, service_quantity: 0).job_task_quote
        quote.job_task_quote_options.create!(job_option: option, price: 3)
        before = described_class.find(order.id).quote_fingerprint
        option.update!(name: "Polish (premium)")
        order.job_tasks.first.update!(title: "Renamed")
        expect(described_class.find(order.id).quote_fingerprint).to eq(before)
      end

      it "raises a network error from the concern when Shopify answers with a non-200 while creating" do
        shopify.status = 502
        expect { order.send(:shopify_draft_order) }.to raise_error(RuntimeError, /Network error: Received HTTP 502/)
      end

      it "raises from the concern when Shopify returns user errors" do
        shopify.user_errors = [{ "field" => "x", "message" => "Bad line item" }]
        expect { order.send(:shopify_draft_order) }.to raise_error(RuntimeError, /Shopify Draft Order Creation Failed: Bad line item/)
      end

      it "checkout_link reports and returns nil instead of raising when creation fails" do
        shopify.status = 502
        expect(Rails.error).to receive(:report).with(an_instance_of(JobOrder::StaleDraftOrderError), hash_including(handled: true))
        expect(order.checkout_link.value).to be_nil
      end

      it "treats an empty (but non-null) draftOrder as found, not gone: no re-create" do
        fingerprint = described_class.find(order.id).quote_fingerprint
        order.update_columns(shopify_draft_order_id: "gid://shopify/DraftOrder/9001", shopify_draft_order_fingerprint: fingerprint)
        allow(shopify).to receive(:query).and_return(ShopSpecHelpers::FakeShopifyAdmin::Response.new(200, { "data" => { "draftOrder" => {} } }))
        expect(order.checkout_link.value).to be_nil
        expect(order.reload.shopify_draft_order_id).to eq("gid://shopify/DraftOrder/9001")
        expect(shopify).to have_received(:query).once
      end
    end
  end
end

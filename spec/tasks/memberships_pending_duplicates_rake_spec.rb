# frozen_string_literal: true

require "rails_helper"
require "rake"

# The unique index on pending memberships forbids the duplicates this task exists to clean up, so each example drops
# it inside its own transaction (rolled back with the example) and inserts the rows directly.
RSpec.describe "memberships:pending_duplicates" do
  include ShopSpecHelpers

  let!(:fake) { stub_shopify_admin! }
  let(:tier) { create(:membership_tier) }
  let(:other_tier) { create(:membership_tier, title_en: "Other tier") }
  let(:member) { create(:user, :regular_user) }
  let(:task) { Rake::Task["memberships:pending_duplicates"] }

  before do
    Rails.application.load_tasks unless Rake::Task.task_defined?("memberships:pending_duplicates")
    task.reenable
    ActiveRecord::Base.connection.remove_index(:memberships, name: "index_memberships_on_pending_user_and_tier", if_exists: true)
  end

  # A pending membership created `age` ago, with a draft id unless `draft` is nil.
  def pending(user: member, tier_for: tier, age: 1.day, draft: :next)
    @draft_seq = @draft_seq.to_i + 1
    gid = draft == :next ? "gid://shopify/DraftOrder/#{@draft_seq}" : draft
    id = Membership.insert_all!([{ user_id: user.id, membership_tier_id: tier_for.id, status: "pending", shopify_draft_order_id: gid,
                                   created_at: age.ago, updated_at: age.ago }]).rows.flatten.first
    Membership.find(id)
  end

  def run(mode = nil, cap: nil)
    task.reenable
    stub_const("ENV", ENV.to_h.except("CONFIRM_MAX_DELETES").merge(cap ? { "CONFIRM_MAX_DELETES" => cap } : {}))
    mode ? task.invoke(mode) : task.invoke
  end

  describe "dry run" do
    it "lists each pair with counts and ids, keeping the row checkout serves (the oldest) and closing the others" do
      kept = pending(age: 3.days)
      undrafted = pending(age: 2.days, draft: nil)
      newest = pending(age: 1.day)

      line = ->(m, role) { "  membership #{m.id} #{role} created #{m.created_at.utc.iso8601} updated #{m.updated_at.utc.iso8601} draft " }
      expected = "user #{member.id}, tier #{tier.id}: 3 pending (ids #{[kept, undrafted, newest].map(&:id).join(", ")})\n" \
                 "#{line[kept, "keep (the row checkout serves: oldest pending)"]}#{kept.shopify_draft_order_id}\n" \
                 "#{line[undrafted, "close"]}none\n#{line[newest, "close"]}#{newest.shopify_draft_order_id}\n" \
                 "1 pair, 3 pending memberships, 2 extra rows to close\n"

      expect { run }.to output(expected).to_stdout
    end

    it "keeps the same row a purchase is served" do
      pending
      pending(age: 2.days)
      served = Membership.claim_pending(member, tier.id)

      expect { run }.to output(/membership #{served.id} keep /).to_stdout
    end

    it "says so when no pair has more than one pending row, ignoring single and closed rows" do
      pending
      pending(tier_for: other_tier)
      %w[failed paid expired].each { |status| create(:membership, user: member, membership_tier: tier, status: status) }

      expect { run }.to output(/no member and tier pair has more than one pending membership/).to_stdout
    end

    it "changes nothing and calls no outside service" do
      pending(age: 2.days)
      pending

      expect { expect { run }.to output.to_stdout }.not_to(change { Membership.order(:id).pluck(:id, :status, :shopify_draft_order_id, :updated_at) })
      expect(fake.calls).to be_empty
      expect(Membership::DuplicateClosure.count).to eq(0)
    end

    it "refuses an unknown mode and a cap that is not a whole number" do
      expect { run("delete") }.to raise_error(SystemExit).and output(/usage/).to_stderr
      expect { run(cap: "lots") }.to raise_error(SystemExit).and output(/whole number/).to_stderr
    end

    it "reports and skips a listed row that no longer exists" do
      kept = pending
      gone = pending
      allow(Membership).to receive(:pending_duplicates).and_return([[member.id, tier.id, [kept.id, gone.id, -1]]])

      expect { run }.to output(/membership #{kept.id} keep .*\n  membership #{gone.id} close .*\n  membership -1 no longer exists: skipped/).to_stdout
    end

    it "lists a pair whose rows are no longer pending without a kept row, closing none" do
      rows = [pending, pending]
      rows.each { |row| row.update_columns(status: "expired") }
      allow(Membership).to receive(:pending_duplicates).and_return([[member.id, tier.id, rows.map(&:id)]])

      expect { run }.to output("user #{member.id}, tier #{tier.id}: 2 pending (ids #{rows.map(&:id).join(", ")})\n" \
                               "1 pair, 2 pending memberships, 0 extra rows to close\n").to_stdout
    end
  end

  describe "apply" do
    it "closes the extra rows' drafts, marks them failed and records each change, keeping the row checkout serves" do
      kept = pending(age: 3.days)
      undrafted = pending(age: 2.days, draft: nil)
      newest = pending(age: 1.day)
      other_pair = [pending(tier_for: other_tier, age: 2.days), pending(tier_for: other_tier)]

      expect { run("apply", cap: "3") }.to output(/membership #{newest.id} closed.*outcomes: closed 3/m).to_stdout

      expect(fake.deleted_ids).to contain_exactly(newest.shopify_draft_order_id, other_pair.last.shopify_draft_order_id)
      expect(Membership.pending.order(:id).ids).to eq([kept.id, other_pair.first.id])
      expect([newest, undrafted, other_pair.last].map { |m| m.reload.status }).to eq(%w[failed failed failed])
      expect(Membership.count).to eq(5)
      expect(Membership::DuplicateClosure.find_by!(membership_id: newest.id)).to have_attributes(
        kept_membership_id: kept.id, shopify_draft_order_id: newest.shopify_draft_order_id, previous_status: "pending",
        previous_updated_at: be_within(1.second).of(1.day.ago), marked_updated_at: newest.reload.updated_at, restored_at: nil
      )
    end

    it "changes nothing when more rows would close than CONFIRM_MAX_DELETES allows" do
      pending(age: 3.days)
      pending(age: 2.days)
      pending

      expect { run("apply", cap: "1") }.to raise_error(SystemExit)
        .and output(/2 extra rows would be closed, more than 1.*CONFIRM_MAX_DELETES=2/m).to_stderr.and output(/to close/).to_stdout
      expect { run("apply") }.to raise_error(SystemExit).and output(/more than 0/).to_stderr.and output(/to close/).to_stdout

      expect(Membership.pending.count).to eq(3)
      expect(fake.calls).to be_empty
    end

    it "is safe to run twice: the second run finds nothing to close and calls no outside service" do
      pending
      pending
      expect { run("apply", cap: "1") }.to output(/outcomes: closed 1/).to_stdout
      calls = fake.calls.size

      expect { run("apply", cap: "1") }.to output(/no member and tier pair.*outcomes: none/m).to_stdout

      expect(fake.calls.size).to eq(calls)
      expect(Membership::DuplicateClosure.count).to eq(1)
    end

    it "marks a row whose draft is already gone from Shopify" do
      pending
      extra = pending
      fake.missing_ids << extra.shopify_draft_order_id

      expect { run("apply", cap: "1") }.to output(/outcomes: closed 1/).to_stdout

      expect(fake.deleted_ids).to be_empty
      expect(extra.reload).to be_failed
    end

    it "stops at a paid draft, leaving that row pending and unrecorded and the rows closed before it closed" do
      pending
      closed_first = pending
      pending(tier_for: other_tier)
      paid_draft = pending(tier_for: other_tier)
      fake.draft_statuses[paid_draft.shopify_draft_order_id] = "COMPLETED"

      expect { run("apply", cap: "2") }.to raise_error(SystemExit)
        .and output(/membership #{paid_draft.id}: draft #{Regexp.escape(paid_draft.shopify_draft_order_id)} is paid; stopped/).to_stderr
        .and output(/membership #{paid_draft.id} paid/).to_stdout

      expect(paid_draft.reload).to be_pending
      expect(fake.deleted_ids).not_to include(paid_draft.shopify_draft_order_id)
      expect(Membership::DuplicateClosure.where(membership_id: paid_draft.id)).to be_empty
      expect(closed_first.reload).to be_failed
    end

    it "leaves the row pending and exits non-zero when Shopify keeps the draft payable" do
      pending
      extra = pending
      fake.delete_user_errors = [{ "field" => "id", "message" => "nope" }]

      expect { run("apply", cap: "1") }.to raise_error(SystemExit)
        .and output(/still pending/).to_stderr
        .and output(/membership #{extra.id} open.*outcomes: open 1/m).to_stdout

      expect(extra.reload).to be_pending
      expect(Membership::DuplicateClosure.count).to eq(0)
    end

    it "never closes a draft the kept row also holds, leaving both rows pending" do
      kept = pending
      extra = pending(draft: kept.shopify_draft_order_id)

      expect { run("apply", cap: "1") }.to raise_error(SystemExit)
        .and output(/membership #{extra.id} changed/).to_stdout.and output(/still pending/).to_stderr

      expect(fake.calls).to be_empty
      expect([kept.reload, extra.reload]).to all(be_pending)
      expect(Membership::DuplicateClosure.count).to eq(0)
    end

    it "never closes a draft any other member's membership holds, leaving every row as it is" do
      pending
      extra = pending
      other = create(:membership, user: create(:user), membership_tier: tier, status: "paid", shopify_draft_order_id: extra.shopify_draft_order_id)

      expect { run("apply", cap: "1") }.to raise_error(SystemExit)
        .and output(/membership #{extra.id} changed/).to_stdout.and output(/still pending/).to_stderr

      expect(fake.calls).to be_empty
      expect(extra.reload).to be_pending
      expect(other.reload).to be_paid
    end

    it "leaves an extra row alone, calling no outside service, once the kept row is no longer pending" do
      kept = pending
      extra = pending
      kept.update_columns(status: "paid")

      expect(extra.close_as_duplicate_of(kept)).to eq(:changed)
      expect(fake.calls).to be_empty
      expect(extra.reload).to be_pending
    end

    it "refuses to close a row in favour of another member's row unless both accounts are allowed" do
      extra = pending
      other = pending(user: create(:user, :regular_user))

      expect(extra.close_as_duplicate_of(other)).to eq(:changed)
      expect(extra.close_as_duplicate_of(other, allowed_user_ids: [extra.user_id])).to eq(:changed)
      expect(fake.calls).to be_empty
      expect(extra.reload).to be_pending

      expect(extra.close_as_duplicate_of(other, allowed_user_ids: [extra.user_id, other.user_id])).to eq(:closed)
    end

    it "leaves a row alone once no row of its pair is pending" do
      kept = pending
      extra = pending
      [kept, extra].each { |row| row.update_columns(status: "paid") }

      expect(extra.reload.close_as_duplicate_of(kept)).to eq(:changed)
      expect(fake.calls).to be_empty
    end

    it "leaves a row the member touched while its draft was being closed, and closes it on the next run" do
      pending
      extra = pending
      fake.on_query = ->(query, _) { extra.touch if query.include?("draftOrderDelete") }

      expect { run("apply", cap: "1") }.to raise_error(SystemExit).and output(/membership #{extra.id} changed/).to_stdout.and output(/still pending/).to_stderr
      expect(extra.reload).to be_pending

      fake.on_query = nil
      fake.missing_ids << extra.shopify_draft_order_id
      expect { run("apply", cap: "1") }.to output(/outcomes: closed 1/).to_stdout
      expect(extra.reload).to be_failed
    end
  end
end

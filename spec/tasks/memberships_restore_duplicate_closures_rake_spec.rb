# frozen_string_literal: true

require "rails_helper"
require "rake"

# Closes duplicates with memberships:pending_duplicates[apply], then puts them back. The unique index on pending
# memberships is dropped inside each example's transaction (rolled back with it) so the duplicates can exist.
RSpec.describe "memberships:restore_duplicate_closures" do
  include ShopSpecHelpers

  let!(:fake) { stub_shopify_admin! }
  let(:tier) { create(:membership_tier) }
  let(:member) { create(:user, :regular_user) }
  let(:index) { Membership::DuplicateClosure::PENDING_UNIQUE_INDEX }
  let(:conn) { ActiveRecord::Base.connection }

  before do
    Rails.application.load_tasks unless Rake::Task.task_defined?("memberships:restore_duplicate_closures")
    conn.remove_index(:memberships, name: index, if_exists: true)
  end

  def pending(age: 1.day)
    @draft_seq = @draft_seq.to_i + 1
    id = Membership.insert_all!([{ user_id: member.id, membership_tier_id: tier.id, status: "pending",
                                   shopify_draft_order_id: "gid://shopify/DraftOrder/#{@draft_seq}",
                                   created_at: age.ago, updated_at: age.ago }]).rows.flatten.first
    Membership.find(id)
  end

  def invoke(name, mode = nil, env: {})
    task = Rake::Task[name]
    task.reenable
    stub_const("ENV", ENV.to_h.except("CONFIRM_MAX_DELETES", "CONFIRM_MAX_RESTORES").merge(env))
    mode ? task.invoke(mode) : task.invoke
  end

  # Apply runs with a cap of 10 restores unless `cap` says otherwise (nil: no cap given).
  def restore(mode = nil, cap: "10") = invoke("memberships:restore_duplicate_closures", mode, env: cap ? { "CONFIRM_MAX_RESTORES" => cap } : {})

  def rows = Membership.order(:id).map(&:attributes)

  def close_extras!(count)
    expect { invoke("memberships:pending_duplicates", "apply", env: { "CONFIRM_MAX_DELETES" => count.to_s }) }.to output(/outcomes: closed #{count}/).to_stdout
  end

  it "gives back the original row state after a close and a restore, saying the draft stays deleted" do
    pending(age: 3.days)
    pending(age: 2.days)
    pending
    original = rows
    close_extras!(2)

    expect { restore("apply") }.to output(/: restored\n.*: restored\noutcomes: restored 2; restored rows are exactly as before, including for the stale checkout expiry; the Shopify draft stays deleted/m).to_stdout

    expect(rows).to eq(original)
    expect(Membership::DuplicateClosure.unrestored).to be_empty
    expect(Membership::DuplicateClosure.count).to eq(2)
  end

  it "lists what it would do without changing anything" do
    pending
    extra = pending
    close_extras!(1)
    closed = rows

    expect { restore }.to output(/membership #{extra.id} \(closed \S+, kept \d+, draft \S+\) back to pending: restorable\n1 to look at; restored rows are exactly as before/).to_stdout
    expect(rows).to eq(closed)
  end

  it "is safe to run twice: the second run finds nothing to restore" do
    pending
    pending
    close_extras!(1)
    expect { restore("apply") }.to output(/restored 1/).to_stdout
    restored = rows

    expect { restore("apply") }.to output(/outcomes: none/).to_stdout
    expect { restore }.to output(/no closed duplicate membership to restore/).to_stdout
    expect(rows).to eq(restored)
  end

  it "refuses a row changed since its closure, changing nothing, and exits non-zero" do
    pending
    extra = pending
    close_extras!(1)
    extra.reload.update_columns(status: "paid")
    changed = rows

    expect { restore("apply") }.to raise_error(SystemExit)
      .and output(/membership #{extra.id} .*: changed/).to_stdout.and output(/not restored/).to_stderr
    expect(rows).to eq(changed)
    expect(Membership::DuplicateClosure.unrestored.count).to eq(1)
  end

  it "refuses a row whose member and tier hold a pending row once the unique index exists" do
    pending
    extra = pending
    close_extras!(1)
    conn.add_index(:memberships, %i[user_id membership_tier_id], name: index, unique: true, where: "status = 'pending'")
    closed = rows

    expect { restore("apply") }.to raise_error(SystemExit).and output(/membership #{extra.id} .*: blocked/).to_stdout.and output(/not restored/).to_stderr
    expect(rows).to eq(closed)
  end

  it "answers :already for a closure restored before, and changes nothing when the row moves between check and update" do
    pending
    extra = pending
    close_extras!(1)
    closure = Membership::DuplicateClosure.find_by!(membership_id: extra.id)
    expect(closure.restore).to eq(:restored)
    expect(closure.restore).to eq(:already)

    close_extras!(1)
    again = Membership::DuplicateClosure.unrestored.find_by!(membership_id: extra.id)
    allow(again).to receive(:restorable_state) do
      extra.reload.touch
      :restorable
    end
    expect(again.restore).to eq(:changed)
    expect(extra.reload).to be_failed
    expect(again.reload.restored_at).to be_nil
  end

  it "refuses an unknown mode and a cap that is not a whole number" do
    expect { restore("delete") }.to raise_error(SystemExit).and output(/usage/).to_stderr
    expect { restore("apply", cap: "lots") }.to raise_error(SystemExit).and output(/CONFIRM_MAX_RESTORES must be a whole number/).to_stderr
  end

  it "changes nothing when more rows would be restored than CONFIRM_MAX_RESTORES allows" do
    pending
    pending
    pending
    close_extras!(2)
    closed = rows

    expect { restore("apply", cap: "1") }.to raise_error(SystemExit)
      .and output(/2 closures would be restored, more than 1: nothing was changed.*CONFIRM_MAX_RESTORES=2/m).to_stderr
    expect { restore("apply", cap: nil) }.to raise_error(SystemExit).and output(/more than 0/).to_stderr
    expect(rows).to eq(closed)
  end

  it "keeps the record when the member is deleted with their memberships, and reports the row gone" do
    pending
    extra = pending
    close_extras!(1)
    record = Membership::DuplicateClosure.find_by!(membership_id: extra.id).attributes

    member.destroy!

    expect(Membership.where(user_id: member.id)).to be_empty
    expect(Membership::DuplicateClosure.find_by!(membership_id: extra.id).attributes).to eq(record)
    expect { restore("apply") }.to raise_error(SystemExit).and output(/membership #{extra.id} .*: gone/).to_stdout.and output(/not restored/).to_stderr
    expect(Membership::DuplicateClosure.find_by!(membership_id: extra.id).restored_at).to be_nil
  end

  it "can close a restored row again, recording a second closure" do
    pending
    extra = pending
    close_extras!(1)
    expect { restore("apply") }.to output(/restored 1/).to_stdout

    close_extras!(1)
    expect(extra.reload).to be_failed
    expect(Membership::DuplicateClosure.where(membership_id: extra.id).count).to eq(2)
  end
end

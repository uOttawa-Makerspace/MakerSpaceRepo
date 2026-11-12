# frozen_string_literal: true

require "rails_helper"
require "rake"

RSpec.describe "lockers:untagged_drafts" do
  include ShopSpecHelpers

  let!(:shopify) { stub_shopify_admin! }
  let(:task) { Rake::Task["lockers:untagged_drafts"] }
  let(:tag) { LockerRental.draft_order_operating_tag }
  let(:orphan) { "gid://shopify/DraftOrder/1" }
  let(:stored) { "gid://shopify/DraftOrder/2" }
  let(:marked) { "gid://shopify/DraftOrder/3" }

  before do
    Rails.application.load_tasks unless Rake::Task.task_defined?("lockers:untagged_drafts")
    task.reenable
  end

  def node(id, tags: [tag], status: "OPEN") = { "id" => id, "status" => status, "tags" => tags }

  def run_task(*args)
    out = StringIO.new
    err = StringIO.new
    original = [$stdout, $stderr]
    $stdout = out
    $stderr = err
    status = nil
    begin
      task.invoke(*args)
    rescue SystemExit => e
      status = e.status
    end
    [out.string, err.string, status]
  ensure
    $stdout, $stderr = original
  end

  let!(:rental) { create(:locker_rental, :await_payment).tap { |r| r.update_column(:shopify_draft_order_id, stored) } }

  before do
    shopify.draft_pages = [[node(orphan), node(stored), node(marked, tags: [tag, "locker_rental:#{rental.id}"]),
                            node("gid://shopify/DraftOrder/4", tags: ["makerepo_other_locker"]),
                            node("gid://shopify/DraftOrder/5", status: "COMPLETED")]]
  end

  it "only lists the untagged drafts no rental stores by default, and changes nothing" do
    out, _err, status = run_task

    expect(out).to include("would close: #{orphan}")
    expect(out).not_to include(stored, marked)
    expect(out).to include("nothing changed")
    expect(status).to be_nil
    expect(shopify.deleted_ids).to be_empty
    expect(rental.reload.shopify_draft_order_id).to eq(stored)
  end

  it "closes only the listed orphans with apply, keeping stored, marked, foreign and paid drafts" do
    _out, _err, status = run_task("apply")

    expect(shopify.deleted_ids).to eq([orphan])
    expect(status).to be_nil
    expect(rental.reload.shopify_draft_order_id).to eq(stored)
  end

  it "never deletes a draft Shopify reports paid when it is fetched" do
    shopify.draft_statuses[orphan] = "COMPLETED"
    out, = run_task("apply")

    expect(shopify.deleted_ids).to be_empty
    expect(out).to include("kept: 2")
  end

  it "is safe to run twice: a draft Shopify no longer has is cleared" do
    run_task("apply")
    task.reenable
    shopify.missing_ids << orphan
    out, _err, status = run_task("apply")

    expect(shopify.deleted_ids).to eq([orphan])
    expect(out).to include("cleared: 1")
    expect(status).to be_nil
  end

  it "deletes nothing over the cap and exits 1" do
    stub_const("LockerRental::UntaggedDraftSweep::MAX_DELETES", 0)
    allow(Rails.error).to receive(:report)
    _out, err, status = run_task("apply")

    expect(shopify.deleted_ids).to be_empty
    expect(err).to include("NOTHING was deleted")
    expect(status).to eq(1)
  end

  it "refuses an unknown argument" do
    _out, err, status = run_task("now")
    expect(status).to eq(1)
    expect(err).to include("usage: rake lockers:untagged_drafts[apply]")
    expect(shopify.calls).to be_empty
  end
end

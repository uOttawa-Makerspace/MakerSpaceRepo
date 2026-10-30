# frozen_string_literal: true

require "rails_helper"
require "rake"

RSpec.describe "job_orders:sweep_orphan_drafts", type: :model do
  include JobOrderSpecHelpers

  let(:owner) { create(:user, :regular_user) }
  let!(:shopify) { stub_shopify_admin! }
  let(:task) { Rake::Task["job_orders:sweep_orphan_drafts"] }

  before do
    seed_job_statuses!
    Rails.application.load_tasks unless Rake::Task.task_defined?("job_orders:sweep_orphan_drafts")
    task.reenable
  end

  def run_task
    out = StringIO.new
    err = StringIO.new
    original = [$stdout, $stderr]
    $stdout = out
    $stderr = err
    status = nil
    begin
      task.invoke
    rescue SystemExit => e
      status = e.status
    end
    [out.string, err.string, status]
  ensure
    $stdout, $stderr = original
  end

  it "prints the counts and exits 0 when everything is resolved" do
    order = make_job_order!(owner: owner, status_key: :completed)
    shopify.draft_pages = [[{ "id" => "gid://shopify/DraftOrder/1", "status" => "OPEN",
                              "tags" => [JobOrder.draft_order_operating_tag, "job_order:#{order.id}"] }]]
    out, _err, status = run_task

    expect(out).to include("deleted: 1").and include("unresolved: 0")
    expect(status).to be_nil
  end

  it "lists the unresolved and exits 1" do
    shopify.status = 502
    expect(Rails.error).to receive(:report).once
    out, err, status = run_task

    expect(out).to include("unresolved: 1")
    expect(err).to include("listing open drafts")
    expect(status).to eq(1)
  end

  it "exits 2 and says so when another sweep is running (a skipped run is not a success)" do
    allow(JobOrder::DraftSweep).to receive(:run).and_return(
      JobOrder::DraftSweep::Report.new(counts: {}, unresolved: [], unresolved_gids: [], skipped: true)
    )
    out, _err, status = run_task

    expect(out).to include("skipped: another sweep is running")
    expect(status).to eq(2)
    expect(Rake::Task["job_orders:sweep_orphan_drafts"].full_comment).to include("2 when skipped")
  end

  it "deletes nothing over the cap and exits 1, until CONFIRM_MAX_DELETES allows it" do
    nodes = Array.new(2) do |i|
      order = make_job_order!(owner: owner, status_key: :completed)
      { "id" => "gid://shopify/DraftOrder/#{i + 1}", "status" => "OPEN", "tags" => [JobOrder.draft_order_operating_tag, "job_order:#{order.id}"] }
    end
    shopify.draft_pages = [nodes]
    stub_const("JobOrder::DraftSweep::MAX_DELETES", 1)
    allow(Rails.error).to receive(:report)
    out, err, status = run_task

    expect(shopify.deleted_ids).to be_empty
    expect(err).to include("NOTHING was deleted", "CONFIRM_MAX_DELETES=2")
    expect(status).to eq(1)

    task.reenable
    stub_const("ENV", ENV.to_h.merge("CONFIRM_MAX_DELETES" => "2"))
    out, _err, status = run_task
    expect(out).to include("deleted: 2")
    expect(status).to be_nil
  end
end

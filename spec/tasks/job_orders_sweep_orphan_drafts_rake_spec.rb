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
    out, err, status = run_task

    expect(out).to include("unresolved: 1")
    expect(err).to include("listing open drafts")
    expect(status).to eq(1)
  end
end

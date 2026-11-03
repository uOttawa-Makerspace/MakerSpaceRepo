# frozen_string_literal: true

require "rails_helper"
require "rake"

RSpec.describe "shop_orders:reapply" do
  include ActiveJob::TestHelper

  let!(:order) do
    ProcessedOrder.receive!(provider: "shopify", order_id: 8800, topic: "orders/paid",
                            payload: { "id" => 8800, "tags" => [Membership.draft_order_operating_tag] }).first
  end

  before do
    Rails.application.load_tasks unless Rake::Task.task_defined?("shop_orders:reapply")
    Rake::Task["shop_orders:reapply"].reenable
  end

  def run(arg) = Rake::Task["shop_orders:reapply"].invoke(arg)

  it "puts a failed order back to received by its provider ref and queues the job" do
    order.update!(status: "failed", attempts: 10, last_error: "ActiveRecord::LockWaitTimeout")
    expect { run("8800") }.to output(/queued again/).to_stdout
    expect(order.reload.status).to eq("received")
    expect(enqueued_jobs.map { |j| j["job_class"] }).to eq(["ApplyProcessedOrderJob"])
  end

  it "finds the order by its row id too" do
    order.update!(status: "failed")
    expect { run(order.id.to_s) }.to output(/queued again/).to_stdout
    expect(order.reload.status).to eq("received")
  end

  %w[received applied].each do |status|
    it "refuses an order that is #{status}" do
      order.update!(status: status)
      expect { run("8800") }.to raise_error(SystemExit).and output(/only failed orders are re-run/).to_stderr
      expect(order.reload.status).to eq(status)
      expect(enqueued_jobs).to be_empty
    end
  end

  it "refuses, reporting the real status, when the order was applied in the meantime" do
    order.update!(status: "failed")
    allow(ProcessedOrder).to receive(:find_by).and_wrap_original do |original, *args, **kw|
      found = original.call(*args, **kw)
      found&.update_columns(status: "applied") # the concurrent run commits after the task read the row
      found
    end
    expect { run("8800") }.to raise_error(SystemExit).and output(/is applied, only failed orders are re-run/).to_stderr
    expect(enqueued_jobs).to be_empty
  end

  it "resets the schedule (attempts, due now, report mark) and hands the order out" do
    order.update!(status: "failed", attempts: 10, reported_at: 1.day.ago, next_attempt_at: 3.days.from_now)
    run("8800")
    expect(order.reload).to have_attributes(status: "received", attempts: 1, reported_at: nil) # reset to 0, then the hand-out counts one
    expect(order.next_attempt_at).to be_within(1.minute).of(Time.current + ProcessedOrder::LEASE)
    expect(enqueued_jobs.map { |j| j["job_class"] }).to eq(["ApplyProcessedOrderJob"])
  end

  it "says so when the job cannot be queued; the dispatcher will queue it" do
    order.update!(status: "failed")
    allow(ApplyProcessedOrderJob).to receive(:perform_later).and_return(false)
    expect { run("8800") }.to output(/the dispatcher will queue it/).to_stdout
    expect(order.reload.status).to eq("received")
    expect(order.next_attempt_at).to be <= Time.current
  end

  it "aborts for an unknown order" do
    expect { run("1234567") }.to raise_error(SystemExit).and output(/no stored order/).to_stderr
  end
end

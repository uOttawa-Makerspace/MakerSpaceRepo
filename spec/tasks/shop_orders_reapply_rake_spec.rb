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

  it "aborts for an unknown order" do
    expect { run("1234567") }.to raise_error(SystemExit).and output(/no stored order/).to_stderr
  end
end

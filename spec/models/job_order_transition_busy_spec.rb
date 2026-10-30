# frozen_string_literal: true

require "rails_helper"

# JobOrder#transition! waits for the order's row lock for a bounded time (ApplicationRecord.own_transaction):
# a holder that keeps it must not pin a web thread, the transition is refused as :busy.
RSpec.describe JobOrder, "transition! lock wait", type: :model do
  include JobOrderSpecHelpers

  self.use_transactional_tests = false

  let!(:owner) { create(:user, :regular_user) }
  let!(:staff) { create(:user, :staff) }
  let!(:rows) { seed_job_statuses! }
  let!(:order) { make_job_order!(owner: owner, status_key: :being_processed) }

  after do
    JobOrderStatus.where(job_order_id: order.id).delete_all
    JobOrder.where(id: order.id).delete_all
    JobStatus.where(id: rows.values.map(&:id)).delete_all
    User.unscoped.where(id: [owner.id, staff.id]).delete_all
  end

  it "returns :busy within the lock timeout while another connection holds the order's row lock" do
    stub_const("ApplicationRecord::LOCK_TIMEOUT", "200ms")
    locked = Queue.new
    release = Queue.new
    holder = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        JobOrder.transaction do
          JobOrder.lock.find(order.id)
          locked << true
          release.pop(timeout: 5)
        end
      end
    rescue StandardError => e
      e
    end
    locked.pop

    started = Time.current
    result = JobOrder.find(order.id).transition!(from: JobStatus::BEING_PROCESSED, to: JobStatus::COMPLETED, actor: staff)
    waited = Time.current - started
    release << true

    expect(holder.value).not_to be_a(StandardError)
    expect(result.reason).to eq(:busy)
    expect(waited).to be < 2
    expect(JobOrderStatus.where(job_order_id: order.id).count).to eq(1)
  end
end

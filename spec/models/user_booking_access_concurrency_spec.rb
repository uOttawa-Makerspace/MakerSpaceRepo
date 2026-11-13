# frozen_string_literal: true

require "rails_helper"

# Real second connections, deterministic interleaving (see training_session_certify_concurrency_spec).
RSpec.describe User, "#approve_booking_access under concurrency", type: :model do
  self.use_transactional_tests = false

  let!(:admin) { create(:user, :admin) }
  let!(:applicant) { create(:user, :regular_user, booking_approval: false) }

  after do
    UserBookingApproval.unscoped.where(user_id: applicant.id).delete_all
    User.unscoped.where(id: [admin.id, applicant.id]).delete_all
  end

  def blocked_backends
    ActiveRecord::Base.connection.select_value(
      "SELECT count(*) FROM pg_stat_activity WHERE wait_event_type = 'Lock' AND datname = current_database()"
    ).to_i
  end

  # The first approval parks right after it chose the request, still holding the user lock. The second
  # approval then runs: with the lock it waits for the first to commit and finds access granted; without
  # it, it picks the same request and both grant it.
  def race_two_approvals
    first = nil
    paused = Queue.new
    resume = Queue.new
    allow_any_instance_of(described_class).to receive(:pending_booking_request).and_wrap_original do |original, *args|
      original.call(*args).tap do
        if Thread.current == first
          first = nil
          paused << true
          resume.pop(timeout: ThreadPause::PARKED_TIMEOUT)
        end
      end
    end

    one = two = nil
    begin
      one = in_thread do
        first = Thread.current
        described_class.find(applicant.id).approve_booking_access(by: admin)
      end
      ThreadPause.await(paused, "the first approval")
      two = in_thread { described_class.find(applicant.id).approve_booking_access(by: admin) }
      deadline = Time.current + 5
      Thread.pass until blocked_backends.positive? || !two.alive? || Time.current > deadline
    ensure
      resume << true
      [one, two].compact.each { |t| t.join(ThreadPause::AWAIT_TIMEOUT) }
    end
    [one.value, two.value]
  end

  it "grants a pending request once when two approvals race" do
    pending = UserBookingApproval.create!(user: applicant, identity: "Other", approved: false, comments: "c", date: Date.current)
    results = race_two_approvals

    expect(results.grep(StandardError)).to be_empty
    expect(results.compact).to eq([pending.id])
    expect(UserBookingApproval.where(user_id: applicant.id).pluck(:approved)).to eq([true])
    expect(applicant.reload.booking_approval).to be(true)
  end

  it "creates one approved request when two approvals race and the user has none" do
    results = race_two_approvals

    expect(results.grep(StandardError)).to be_empty
    expect(results.compact.size).to eq(1)
    expect(UserBookingApproval.where(user_id: applicant.id).count).to eq(1)
  end
end

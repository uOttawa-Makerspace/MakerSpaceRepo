# frozen_string_literal: true

require "rails_helper"

# Real second connections, deterministic interleaving. Two requests of one volunteer for one task are approved
# at the same moment: the first pauses after finding no award, just before creating it. The second must wait for
# the volunteer's row lock and then see the award; without the lock it creates a second award.
RSpec.describe VolunteerTaskRequest, "#pay_award under concurrency", type: :model do
  self.use_transactional_tests = false

  let!(:volunteer) { create(:user, :volunteer_with_volunteer_program) }
  let!(:task) { create(:volunteer_task, cc: 12, hours: 3.5) }
  let!(:first) { create(:volunteer_task_request, :not_processed, user: volunteer, volunteer_task: task) }
  let!(:second) { create(:volunteer_task_request, :not_processed, user: volunteer, volunteer_task: task) }

  after do
    VolunteerHour.where(user_id: volunteer.id).delete_all
    CcMoney.where(user_id: volunteer.id).delete_all
    VolunteerTaskRequest.where(user_id: volunteer.id).delete_all
    task.destroy
    Space.where(id: task.space_id).delete_all
    User.unscoped.where(id: volunteer.id).destroy_all
  end

  def in_thread(&block)
    Thread.new do
      ActiveRecord::Base.connection_pool.with_connection(&block)
    rescue StandardError => e
      e
    end
  end

  def blocked_backends
    ActiveRecord::Base.connection.select_value(
      "SELECT count(*) FROM pg_stat_activity WHERE wait_event_type = 'Lock' AND datname = current_database()"
    ).to_i
  end

  def approve(id)
    request = VolunteerTaskRequest.find(id)
    request.with_lock do
      request.update!(approval: true)
      request.pay_award
    end
  end

  it "pays one award and one hour row when two requests for one task are approved together" do
    leader = nil
    paused = Queue.new
    resume = Queue.new
    allow(CcMoney).to receive(:create_cc_money_from_approval).and_wrap_original do |original, *args|
      if Thread.current == leader
        leader = nil
        paused << true
        resume.pop(timeout: ThreadPause::PARKED_TIMEOUT)
      end
      original.call(*args)
    end

    one = in_thread do
      leader = Thread.current
      approve(first.id)
    end
    ThreadPause.await(paused)
    two = in_thread { approve(second.id) }
    deadline = Time.current + 5
    Thread.pass until blocked_backends.positive? || !two.alive? || Time.current > deadline
    resume << true

    results = [one.value, two.value]
    expect(results.grep(StandardError)).to be_empty
    expect(VolunteerTaskRequest.find(first.id)).to be_award_paid
    expect(CcMoney.where(user_id: volunteer.id, volunteer_task_id: task.id).pluck(:cc)).to eq([12])
    expect(VolunteerHour.where(user_id: volunteer.id, volunteer_task_id: task.id).pluck(:total_time)).to eq([3.5])
    expect(VolunteerTaskRequest.where(user_id: volunteer.id).pluck(:approval)).to eq([true, true])
  end

  # Two writers that do not take the volunteer's row lock insert the same award at once. The first parks inside
  # its transaction right after its insert; the second then waits on the unique index. When the first commits the
  # second is refused, which counts as already paid: it gets nil, writes nothing and raises nothing.
  it "pays one award when two unlocked writers insert it at once, the loser getting nil" do
    leader = nil
    inserted = Queue.new
    resume = Queue.new
    allow(CcMoney).to receive(:create).and_wrap_original do |original, *args|
      row = original.call(*args)
      if Thread.current == leader
        leader = nil
        inserted << true
        resume.pop(timeout: ThreadPause::PARKED_TIMEOUT)
      end
      row
    end

    one = in_thread do
      leader = Thread.current
      CcMoney.create_cc_money_from_approval(task.id, volunteer.id, 12)
    end
    ThreadPause.await(inserted)
    two = in_thread { CcMoney.create_cc_money_from_approval(task.id, volunteer.id, 12) }
    deadline = Time.current + 5
    Thread.pass until blocked_backends.positive? || !two.alive? || Time.current > deadline
    resume << true

    expect([one.value, two.value].grep(StandardError)).to be_empty
    expect(one.value).to be_a(CcMoney)
    expect(two.value).to be_nil
    expect(CcMoney.where(user_id: volunteer.id, volunteer_task_id: task.id).pluck(:cc)).to eq([12])
  end

  # The request's own check read stale data and the award already exists: the refused insert counts as already
  # paid, so no hour row is written either and the committed first award is untouched.
  it "treats an award the database refuses as already paid" do
    CcMoney.create_cc_money_from_approval(task.id, volunteer.id, 12)
    allow_any_instance_of(described_class).to receive(:award_paid?).and_return(false)

    expect(in_thread { first.pay_award }.value).not_to be_a(StandardError)

    expect(CcMoney.where(user_id: volunteer.id, volunteer_task_id: task.id).pluck(:cc)).to eq([12])
    expect(VolunteerHour.where(user_id: volunteer.id, volunteer_task_id: task.id)).to be_empty
    expect(volunteer.reload.wallet).to eq(CcMoney.where(user_id: volunteer.id).sum(:cc))
  end
end

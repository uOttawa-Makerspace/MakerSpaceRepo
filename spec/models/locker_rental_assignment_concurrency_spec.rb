# frozen_string_literal: true

require "rails_helper"

# Two simultaneous assignments of one locker both pass the uniqueness validation (neither sees the other's
# uncommitted row). The partial unique index lets one insert through; the other is refused with the
# validation's own message, not an error.
RSpec.describe LockerRental, "assigning one locker twice at once", type: :model do
  self.use_transactional_tests = false

  let!(:locker) { create(:locker) }
  let!(:decider) { create(:user, :staff) }
  let!(:first_renter) { create(:user) }
  let!(:second_renter) { create(:user) }

  after do
    LockerRental.where(locker_id: locker.id).delete_all
    locker.destroy
    locker.locker_size&.destroy
    User.unscoped.where(id: [decider.id, first_renter.id, second_renter.id]).delete_all
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

  def assignment(renter, state: :active)
    described_class.new(rented_by: renter, locker: locker, state: state, requested_as: "general",
                        decided_by: decider, owned_until: 30.days.from_now)
  end

  it "saves one assignment and refuses the other with the validation message" do
    paused = Queue.new
    resume = Queue.new
    first = in_thread do
      described_class.transaction do
        assignment(first_renter).save!
        paused << true
        resume.pop(timeout: ThreadPause::PARKED_TIMEOUT)
      end
      :committed
    end
    ThreadPause.await(paused)
    rental = assignment(second_renter, state: :await_payment)
    second = in_thread { [rental.save, rental.errors.full_messages] }
    deadline = Time.current + 5
    Thread.pass while blocked_backends.zero? && Time.current < deadline
    resume << true

    expect(first.value).to eq(:committed)
    saved, messages = second.value
    expect(saved).to be(false)
    expect(messages).to eq(["Locker has already been taken"])
    expect(described_class.where(locker_id: locker.id).count).to eq(1)
  end

  it "leaves an enclosing transaction usable after the refused insert" do
    assignment(first_renter).save!
    rental = assignment(second_renter)

    described_class.transaction do
      expect(rental.save(validate: false)).to be(false)
      expect(described_class.where(locker_id: locker.id).count).to eq(1)
    end
  end

  it "does not hide other unique violations" do
    rental = assignment(first_renter)
    rental.save!
    clash = assignment(second_renter)
    allow(clash).to receive(:_create_record).and_raise(ActiveRecord::RecordNotUnique, "some_other_index")

    expect { clash.save(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
  end
end

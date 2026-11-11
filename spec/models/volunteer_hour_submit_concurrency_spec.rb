# frozen_string_literal: true

require "rails_helper"

# Real second connections, deterministic interleaving. Two identical submissions both pass the pending-repeat
# check; the first is parked just before its INSERT, the second is saved, then the first is released and the unique
# index refuses it. That one must answer with the "awaiting review" message instead of raising.
RSpec.describe VolunteerHour, "#save_hand_logged under concurrency", type: :model do
  self.use_transactional_tests = false

  let!(:volunteer) { create(:user, :volunteer_with_volunteer_program) }
  let!(:task) { create(:volunteer_task) }
  let(:attrs) { { volunteer_task_id: task.id, date_of_task: Time.zone.parse("2026-03-04 00:00"), total_time: 2.5 } }

  before { create(:volunteer_task_join, volunteer_task: task, user: volunteer, state: "joined", user_type: "Volunteer") }

  after do
    VolunteerHour.where(user_id: volunteer.id).delete_all
    VolunteerTaskJoin.where(user_id: volunteer.id).delete_all
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

  it "stores one row and answers the second submission with the awaiting-review message" do
    leader = nil
    parked = Queue.new
    resume = Queue.new
    allow_any_instance_of(VolunteerHour).to receive(:valid?).and_wrap_original do |original, *args|
      outcome = original.call(*args)
      if Thread.current == leader
        leader = nil
        parked << true
        resume.pop(timeout: ThreadPause::PARKED_TIMEOUT)
      end
      outcome
    end

    hours = [VolunteerHour.new(user: volunteer), VolunteerHour.new(user: volunteer)]
    one = in_thread do
      leader = Thread.current
      hours[0].save_hand_logged(attrs)
    end
    ThreadPause.await(parked)
    two = in_thread { hours[1].save_hand_logged(attrs) }
    expect(two.value).to be(true)
    resume << true

    expect([one.value, two.value]).to eq([false, true])
    expect(hours[0].errors.full_messages).to eq(["You already sent these hours for this task and day; they are awaiting review."])
    expect(VolunteerHour.where(user_id: volunteer.id).count).to eq(1)
  end
end

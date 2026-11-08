# frozen_string_literal: true

require "rails_helper"

# An admin edit that was loaded before another admin assigns or revokes the key. The assign or
# revoke parks holding the key row lock; the edit must block on it, then judge the stored state.
RSpec.describe Key, "edit under concurrency", type: :model do
  self.use_transactional_tests = false

  let!(:space) { create(:space) }
  let!(:holder) { create(:user, :staff) }
  let!(:supervisor) { create(:user, :admin) }
  let!(:key) { create(:key, :regular_key_type, :inventory_status, space: space, number: 32) }

  after do
    KeyTransaction.where(key_id: key.id).delete_all
    Key.where(id: key.id).delete_all
    User.unscoped.where(id: [holder.id, supervisor.id]).delete_all
    space.destroy
  end

  def wait_until_blocked_on_lock(release, timeout: 5)
    deadline = Time.current + timeout
    loop do
      blocked = ActiveRecord::Base.connection.select_value(
        "SELECT count(*) FROM pg_stat_activity WHERE wait_event_type = 'Lock' AND datname = current_database()"
      ).to_i
      return if blocked.positive?
      (release << true; raise "no backend became blocked") if Time.current > deadline

      Thread.pass
    end
  end

  def in_thread(&block)
    Thread.new do
      ActiveRecord::Base.connection_pool.with_connection(&block)
    rescue StandardError => e
      e
    end
  end

  # Loads the key for an edit, then lets another request hand it out or take it back while holding
  # the row lock, and runs the edit against the key as loaded. Returns the edit's outcome.
  def edit_during(other_request, attributes)
    stale = Key.find(key.id)
    paused = Queue.new
    resume = Queue.new
    other = in_thread do
      Key.transaction do
        Key.find(key.id).tap(&:lock!)
        paused << true
        resume.pop(timeout: ThreadPause::PARKED_TIMEOUT)
        other_request.call(Key.find(key.id))
      end
    end
    ThreadPause.await(paused)
    edit = in_thread { stale.update_from_edit!(attributes) }
    wait_until_blocked_on_lock(resume)
    resume << true
    other.value
    edit.value
  end

  it "an edit loaded before an assign keeps the key held and ignores the posted status" do
    result = edit_during(->(k) { k.assign_to!(holder, { supervisor_id: supervisor.id }, 0) },
                         { status: "lost", additional_info: "edited" })

    expect(result).to be_truthy
    expect(Key.find(key.id)).to have_attributes(status: "held", user_id: holder.id, additional_info: "edited")
  end

  it "an edit loaded before a revoke is refused when it posts the held status" do
    key.assign_to!(holder, { supervisor_id: supervisor.id }, 0)
    key.reload
    result = edit_during(:revoke!.to_proc, { status: "held", additional_info: "edited" })

    expect(result).to be_a(Key::StateError)
    expect(Key.find(key.id)).to have_attributes(status: "inventory", user_id: nil)
    expect(Key.find(key.id).additional_info).not_to eq("edited")
  end
end

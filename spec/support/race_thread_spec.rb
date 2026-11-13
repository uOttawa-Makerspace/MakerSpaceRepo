# frozen_string_literal: true

require "rails_helper"

RSpec.describe RaceThread do
  self.use_transactional_tests = false

  # A concurrency example that fails while one of its threads is still working must not have that thread
  # write after the example's cleanup has run: the row would stay in the database for every later example.
  it "waits for a thread still writing when the example body fails, before the group's after hooks run" do
    name = "racethread#{SecureRandom.hex(4)}"
    seen_by_cleanup = nil
    group = RSpec.describe("example that fails with a thread still writing") do
      self.use_transactional_tests = false

      after do
        seen_by_cleanup = Space.where(name: name).exists?
        Space.where(name: name).delete_all
      end

      it("raises while its thread is parked before the write") do
        parked = Queue.new
        in_thread do
          parked << true
          Queue.new.pop(timeout: 0.2)
          Space.create!(name: name, keycode: "key#{name}")
        end
        ThreadPause.await(parked)
        raise "body failed"
      end
    end
    RSpec.world.example_groups.delete(group) # run it here, not again as part of the suite

    group.run(RSpec::Core::NullReporter)

    expect(group.examples.first.exception.message).to eq("body failed")
    expect(seen_by_cleanup).to be(true)
  end

  it "has nothing to wait for in an example that started no thread" do
    expect { settle_race_threads }.not_to raise_error
  end
end

# frozen_string_literal: true

require "rails_helper"

RSpec.describe CommittedRowsGuard do
  # a transactional example pins one connection, whose open transaction would keep a SET LOCAL
  self.use_transactional_tests = false

  it "counts every table without leaving a lock timeout on the pooled connection" do
    pool = ActiveRecord::Base.connection_pool
    conn = pool.checkout
    default = conn.select_value("SHOW lock_timeout")
    pool.checkin(conn)

    counts = described_class.counts
    expect(counts).to include("users" => be_a(Integer))

    conn = pool.checkout
    begin
      expect(conn.select_value("SHOW lock_timeout")).to eq(default)
    ensure
      pool.checkin(conn)
    end
  end

  describe "lock waits" do
    def lock_timeout_of(conn)
      conn.select_value("SHOW lock_timeout")
    end

    it "every pooled connection bounds a lock wait at ThreadPause::LOCK_TIMEOUT, even after a RESET" do
      seen = Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do |conn|
          before = lock_timeout_of(conn)
          conn.execute("RESET lock_timeout")
          [before, lock_timeout_of(conn)]
        end
      end.value
      expect(seen).to eq(["#{ThreadPause::LOCK_TIMEOUT}s"] * 2)
    end

    # A request ends by returning the example's connection to the pool, and a thread of the example may
    # then check that same connection out. The guard must not run anything on it once the example is over.
    it "leaves alone a connection the example's request returned and another thread then took" do
      holder = nil
      paused = Queue.new
      resume = Queue.new
      group = RSpec.describe("example whose connection moves to another thread") do
        self.use_transactional_tests = false
        it("hands its connection to a parked thread") do
          mine = ActiveRecord::Base.connection
          Rails.application.executor.wrap { mine.select_value("SELECT 1") }
          holder = Thread.new do
            ActiveRecord::Base.connection_pool.with_connection do |conn|
              LockerRental.transaction do
                seen = [conn.equal?(mine), conn.select_value("SHOW lock_timeout")]
                paused << true
                resume.pop(timeout: ThreadPause::PARKED_TIMEOUT)
                seen << conn.select_value("SHOW lock_timeout")
              end
            end
          end
          ThreadPause.await(paused)
        end
      end
      RSpec.world.example_groups.delete(group)
      begin
        group.run(RSpec::Core::NullReporter)
        # the guard reports the parked thread's lease and runs nothing on that connection
        expect(group.examples.first.exception.message).to include("leased to a running thread")
      ensure
        resume << true
      end
      took_it, during, after_the_example = holder.value
      expect(took_it).to be(true)
      expect(after_the_example).to eq(during)
    end
  end

  describe "connections left leased to another thread" do
    def run_example(&body)
      group = RSpec.describe("example that starts a thread") do
        self.use_transactional_tests = false
        it("runs a query on another thread", &body)
      end
      RSpec.world.example_groups.delete(group) # run it here, not again as part of the suite
      group.run(RSpec::Core::NullReporter)
      group.examples.first.exception
    end

    it "fails an example whose finished thread still holds the connection it leased" do
      error = run_example do
        Thread.new { ActiveRecord::Base.connection.select_value("SELECT 1") }.join
      end
      expect(error.message).to include("1 pooled connection(s) leased to a finished thread")
    ensure
      ActiveRecord::Base.connection_pool.reap # takes back the finished thread's connection
    end

    it "passes an example whose threads were started with in_thread and race_thread and joined" do
      error = run_example do
        in_thread { ActiveRecord::Base.connection.select_value("SELECT 1") }.join
        race_thread { User.connection.select_value("SELECT 1") }.join
      end
      expect(error).to be_nil
    end
  end

  describe "suite-start check" do
    it "passes on a database holding only the seeded lookup rows" do
      expect(described_class.stale_rows("users" => 0, "order_statuses" => 2)).to eq({})
    end

    it "names the table of a leftover row from an earlier run" do
      stale = described_class.stale_rows("users" => 1, "cc_moneys" => 0, "order_statuses" => 2)
      expect(stale).to eq("users" => 1)
      expect(described_class.stale_rows_message(stale)).to include("users (1)").and include("Recreate the worker test databases")
    end

    it "finds no leftover rows in this worker's database" do
      expect(described_class.stale_rows).to eq({})
    end
  end

  describe "leftover rows of a failing example" do
    it "reports the leaked rows next to the example's own error" do
      group = RSpec.describe("leaky committed example") do
        self.use_transactional_tests = false
        it("fails after committing a row") do
          FactoryBot.create(:user, username: "guardprobe")
          raise "original failure"
        end
      end
      RSpec.world.example_groups.delete(group) # run it here, not again as part of the suite
      begin
        group.run(RSpec::Core::NullReporter)
        example = group.examples.first
        messages = [example.exception, *Array(example.exception.try(:all_exceptions))].map(&:message).join("\n")
        expect(messages).to include("original failure").and include("users (+1)")
      ensure
        User.unscoped.where(username: "guardprobe").delete_all
      end
    end
  end
end

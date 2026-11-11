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

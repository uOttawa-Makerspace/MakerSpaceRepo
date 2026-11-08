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
end

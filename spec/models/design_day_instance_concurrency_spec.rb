# frozen_string_literal: true

require "rails_helper"

# Real second connections, deterministic interleaving (see webhook_registrar_concurrency_spec).
RSpec.describe DesignDay, ".instance when two first visits overlap", type: :model do
  self.use_transactional_tests = false

  before { described_class.unscoped.delete_all }

  after { described_class.unscoped.delete_all }

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

  it "leaves one row and gives the losing visit the winner's row" do
    paused = Queue.new
    resume = Queue.new
    one = two = nil
    begin
      one = in_thread do
        described_class.transaction do
          described_class.create!(day: Date.new(2026, 5, 5), sheet_key: "winner", is_live: true)
          paused << true
          resume.pop(timeout: ThreadPause::PARKED_TIMEOUT)
        end
      end
      ThreadPause.await(paused, "the first insert")
      two = in_thread { described_class.instance }
      deadline = Time.current + 5
      Thread.pass until blocked_backends.positive? || !two.alive? || Time.current > deadline
      expect(two).to be_alive # its insert waits for the first to finish
    ensure
      resume << true
      [one, two].compact.each { |t| t.join(ThreadPause::AWAIT_TIMEOUT) }
    end

    expect(one.value).not_to be_a(StandardError)
    expect(two.value).to be_a(described_class).and have_attributes(sheet_key: "winner")
    expect(described_class.unscoped.count).to eq(1)
  end
end

# frozen_string_literal: true

require "rails_helper"

RSpec.describe BulkMailRun do
  let!(:users) { create_list(:user, 5, :regular_user) }
  let(:scope) { User.where(id: users.map(&:id)) }

  def run_with(period = "2026", **opts)
    seen = []
    described_class.new("spec", period, **opts).each_batch(scope, 2) { |batch| seen.concat(batch.map(&:id)) }
    seen
  end

  it "hands over every user once, in id order and in batches" do
    expect(run_with).to eq(users.map(&:id).sort)
  end

  it "hands over nobody on a second run in the same period" do
    run_with
    expect(run_with).to be_empty
    expect(described_class.new("spec", "2026")).to be_done
  end

  it "starts again in a new period" do
    run_with
    expect(run_with("2027")).to eq(users.map(&:id).sort)
  end

  it "hands over everyone again when forced" do
    run_with
    expect(run_with(force: true)).to eq(users.map(&:id).sort)
  end

  it "continues after the last batch claimed when a run is interrupted" do
    handled = []
    expect do
      described_class.new("spec", "2026").each_batch(scope, 2) do |batch|
        raise "mail down" if handled.size == 2
        handled.concat(batch.map(&:id))
      end
    end.to raise_error("mail down")
    expect(handled.size).to eq(2)
    expect(run_with).to eq(users.map(&:id).sort.drop(2))
  end

  it "does not hand a batch over when another run has claimed it" do
    allow(Setting).to receive(:swap).and_return(false)
    expect(run_with).to be_empty
  end

  it "returns the number of batches mailed" do
    expect(described_class.new("spec", "2026").each_batch(scope, 2) { |_| }).to eq(3)
    expect(described_class.new("spec", "2026").each_batch(scope, 2) { |_| }).to eq(0)
  end

  it "mails one user at a time with each_user and repeats only the user whose mail failed" do
    handled = []
    expect do
      described_class.new("spec", "2026").each_user(scope) do |user|
        raise "mail down" if handled.size == 2
        handled << user.id
      end
    end.to raise_error("mail down")
    again = []
    count = described_class.new("spec", "2026").each_user(scope) { |user| again << user.id }
    expect(again).to eq(users.map(&:id).sort.drop(2))
    expect(count).to eq(3)
  end

  it "refuses a stored progress value that is not a user id" do
    Setting.set("bulk_mail:spec:2026", "garbage")
    expect { run_with }.to raise_error(/Unexpected progress "garbage" in setting bulk_mail:spec:2026/)
  end

  it "gives the claim back when the run is interrupted with Ctrl-C or SIGTERM" do
    [Interrupt.new, SignalException.new("TERM")].each_with_index do |signal, i|
      period = "sig#{i}"
      expect do
        described_class.new("spec", period).each_user(scope) { |_| raise signal }
      end.to raise_error(SignalException)
      seen = []
      described_class.new("spec", period).each_user(scope) { |user| seen << user.id }
      expect(seen).to eq(users.map(&:id).sort)
    end
  end

  it "starts over when the stored progress is empty" do
    Setting.set("bulk_mail:spec:2026", "")
    expect(run_with).to eq(users.map(&:id).sort)
  end

  it "lets the original error propagate and reports the claim when handing it back fails" do
    allow(Setting).to receive(:swap).and_call_original
    allow(Setting).to receive(:swap).with("bulk_mail:spec:2026", anything, nil).and_raise(ActiveRecord::ConnectionNotEstablished, "db down")
    reported = []
    subscriber = Class.new { define_method(:report) { |error, **opts| reported << [error, opts[:context]] } }.new
    Rails.error.subscribe(subscriber)

    run = -> { described_class.new("spec", "2026").each_user(scope) { |_| raise "mail down" } }

    expect(&run).to raise_error("mail down").and output(/Setting\.set\("bulk_mail:spec:2026", nil\)/).to_stderr
    expect(reported.map { |error, _| error.message }).to eq(["db down"])
    expect(reported.first.last).to eq(key: "bulk_mail:spec:2026", claimed: users.map(&:id).min.to_s)
  ensure
    Rails.error.unsubscribe(subscriber)
  end

  it "still raises the original error when the operator message cannot be written either" do
    allow(Setting).to receive(:swap).and_call_original
    allow(Setting).to receive(:swap).with("bulk_mail:spec:2026", anything, nil).and_raise(ActiveRecord::ConnectionNotEstablished, "db down")
    dead_terminal = Class.new do
      def write(*) = raise(Errno::EPIPE)
      def puts(*) = raise(Errno::EPIPE)
    end.new
    original = $stderr
    $stderr = dead_terminal

    expect { described_class.new("spec", "2026").each_user(scope) { |_| raise "mail down" } }.to raise_error("mail down")
  ensure
    $stderr = original
  end
end

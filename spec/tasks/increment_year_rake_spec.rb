# frozen_string_literal: true

require "rails_helper"
require "rake"

RSpec.describe "increment_year:increment_one_year" do
  include ActiveSupport::Testing::TimeHelpers

  let!(:student) do
    create(:user, :regular_user, :student, year_of_study: "2", created_at: Time.zone.local(2024, 3, 10))
  end

  before do
    Rails.application.load_tasks unless Rake::Task.task_defined?("increment_year:increment_one_year")
  end

  def run_task
    Rake::Task["increment_year:increment_one_year"].reenable
    Rake::Task["increment_year:increment_one_year"].invoke
  end

  it "moves the students created in this month up one year" do
    travel_to(Time.zone.local(2026, 3, 15)) { run_task }

    expect(student.reload.year_of_study).to eq("3")
  end

  it "changes nothing when it runs a second time in the same month" do
    travel_to(Time.zone.local(2026, 3, 15)) { run_task }
    travel_to(Time.zone.local(2026, 3, 28)) { run_task }

    expect(student.reload.year_of_study).to eq("3")
  end

  it "runs again the next time that month comes round" do
    travel_to(Time.zone.local(2026, 3, 15)) { run_task }
    travel_to(Time.zone.local(2027, 3, 15)) { run_task }

    expect(student.reload.year_of_study).to eq("4")
  end

  it "runs again in a later month for the students created in that month" do
    other = create(:user, :regular_user, :student, year_of_study: "1", created_at: Time.zone.local(2025, 4, 2))
    travel_to(Time.zone.local(2026, 3, 15)) { run_task }
    travel_to(Time.zone.local(2026, 4, 15)) { run_task }

    expect([student.reload.year_of_study, other.reload.year_of_study]).to eq(%w[3 2])
  end

  it "does not record the month when the run fails, so it can be repeated" do
    allow(User).to receive(:active).and_raise(ActiveRecord::StatementInvalid, "boom")

    travel_to(Time.zone.local(2026, 3, 15)) { expect { run_task }.to raise_error(ActiveRecord::StatementInvalid) }

    expect(Setting.get("increment_year_last_run")).to be_nil
  end
end

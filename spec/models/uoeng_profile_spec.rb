# frozen_string_literal: true

require "rails_helper"

RSpec.describe UoengProfile, type: :model do
  let(:user) { create(:user, :regular_user) }
  let(:answer) do
    { "emplid" => 300_000_001, "faculty" => "GENIE", "program" => "CEG", "program_level" => "undergraduate",
      "fulltime" => true, "student_this_semester" => true }
  end

  describe ".record!" do
    it "reads only the fields it keeps, and ignores values of an unexpected type" do
      described_class.record!(user, answer.merge("program" => ["CEG"], "fulltime" => "yes", "emplid" => " 42 "), source: "email")

      expect(user.reload.uoeng_profile).to have_attributes(
        emplid: "42", faculty: "Engineering", program_code: nil, full_time: nil, current_semester: true, level: "undergrad"
      )
    end

    it "is refused by the database for an unknown source" do
      expect { described_class.record!(user, answer, source: "card") }.to raise_error(ActiveRecord::StatementInvalid)
    end
  end

  it "is removed with its user" do
    user.record_uoeng_answer!(answer)

    expect { user.destroy! }.to change(described_class, :count).by(-1)
  end

  describe "a card tap and a staff check recording at once" do
    self.use_transactional_tests = false

    let!(:racer) { create(:user, :regular_user, student_id: "300000001") }

    after do
      described_class.where(user_id: racer.id).delete_all
      racer.destroy!
    end

    it "leaves one row for the user" do
      start = Queue.new
      threads = Array.new(2) do |i|
        race_thread do
          start.pop(timeout: ThreadPause::PARKED_TIMEOUT)
          User.find(racer.id).record_uoeng_answer!(answer.merge("program" => "P#{i}"))
        end
      end
      2.times { start << true }
      threads.each(&:join)

      expect(described_class.where(user_id: racer.id).pluck(:program_code)).to contain_exactly("P0").or contain_exactly("P1")
    end
  end
end

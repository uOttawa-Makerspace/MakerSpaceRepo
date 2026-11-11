require "rails_helper"

RSpec.describe Program, type: :model do
  describe "Association" do
    context "belongs_to" do
      it { should belong_to(:user).without_validating_presence }
    end
  end

  describe "Validations" do
    context "user" do
      it do
        should validate_presence_of(:user).with_message("A user is required.")
      end
      it do
        user = create(:user)
        user2 = create(:user)
        program = create(:program, :development_program, user_id: user.id)
        program2 = create(:program, :development_program, user_id: user2.id)
        program3 = build(:program, :development_program, user_id: user2.id)

        expect(program).to be_valid
        expect(program2).to be_valid
        expect(program3).to_not be_valid
      end
      it do
        should validate_presence_of(:program_type).with_message(
                 "The type of the program is required. Either 'Volunteer Program', 'Development Program', or 'Teams Program'"
               )
      end
    end
  end

  describe ".join" do
    let(:user) { create(:user) }

    it "adds the program and reports it" do
      expect(Program.join(user, Program::DEV_PROGRAM)).to be(true)
      expect(user.programs.pluck(:program_type, :active)).to eq([[Program::DEV_PROGRAM, true]])
    end

    it "does nothing and reports it when the user already holds the program" do
      expect(Program.join(user, Program::DEV_PROGRAM)).to be(true)
      expect(Program.join(user, Program::DEV_PROGRAM)).to be(false)
      expect(user.programs.count).to eq(1)
    end

    it "keeps the existing row untouched when joining again" do
      existing = create(:program, :volunteer_program, user: user, active: false)
      expect { Program.join(user, Program::VOLUNTEER) }.not_to(change { existing.reload.attributes })
    end

    it "names no index, so it works before the unique index exists and is still safe to repeat" do
      sql = []
      listener = ->(*, payload) { sql << payload[:sql] if payload[:sql].start_with?("INSERT INTO \"programs\"") }
      ActiveSupport::Notifications.subscribed(listener, "sql.active_record") do
        Program.join(user, Program::TEAMS)
        Program.join(user, Program::TEAMS)
      end

      expect(sql.size).to eq(2)
      expect(sql).to all(match(/ON CONFLICT\s+DO NOTHING/))
      expect(sql.join).not_to include("index_programs_on_user_id_and_program_type")
      expect(user.programs.count).to eq(1)
    end

    it "adds a different program next to the first" do
      Program.join(user, Program::DEV_PROGRAM)
      Program.join(user, Program::TEAMS)
      expect(user.programs.pluck(:program_type)).to match_array([Program::DEV_PROGRAM, Program::TEAMS])
    end
  end

  describe "the database" do
    it "refuses a second row for the same user and program even when validations are skipped" do
      user = create(:user)
      create(:program, :volunteer_program, user: user)
      second = build(:program, :volunteer_program, user: user)
      expect { second.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end
end

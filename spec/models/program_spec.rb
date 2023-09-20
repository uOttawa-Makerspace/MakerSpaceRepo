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
end

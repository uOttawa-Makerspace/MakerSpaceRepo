require "rails_helper"

RSpec.describe Program, type: :model do
  describe "Association" do
    context "belongs_to" do
      it { should belong_to(:user) }
    end
  end

  describe "Validations" do
    context "user" do
      it do
        should validate_presence_of(:user).with_message("A user is required.")
      end
      it do
        user = create(:user)
        program_type = create(:program).program_type
        # create an existing record to test uniqueness
        existing_record =
          create(:program, user: user, program_type: program_type)

        # create a new record with the same user and program type
        new_record = build(:program, user: user, program_type: program_type)

        # expect the new record to be invalid and to have the correct error message
        expect(new_record).not_to be_valid
        expect(new_record.errors[:user]).to include(
          "An user can only join a program once"
        )
      end
      it do
        should validate_presence_of(:program_type).with_message(
                 "The type of the program is required. Either 'Volunteer Program' or 'Development Program'"
               )
      end
    end
  end
end

require "rails_helper"

RSpec.describe RequireTraining, type: :model do
  describe "Association" do
    context "belongs_to" do
      it { should belong_to(:training).without_validating_presence }
      it { should belong_to(:volunteer_task).without_validating_presence }
    end
  end

  describe "Validations" do
    context "password private" do
      it do
        should validate_presence_of(:training_id).with_message(
                 "A training must be selected"
               )
      end
    end
  end
end

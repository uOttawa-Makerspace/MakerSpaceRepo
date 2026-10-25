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

  describe "Chunk 12: validation message" do
    it "requires a training with the user-facing message" do
      rt = RequireTraining.new(volunteer_task: create(:volunteer_task))
      expect(rt).not_to be_valid
      expect(rt.errors[:training_id]).to eq(["A training must be selected"])
    end

    it "is destroyed with its training" do
      rt = create(:require_training)
      expect { rt.training.destroy }.to change(RequireTraining, :count).by(-1)
    end
  end
end

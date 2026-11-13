require "rails_helper"

RSpec.describe RequireTraining, type: :model do
  describe "Association" do
    context "belongs_to" do
      it { should belong_to(:training).without_validating_presence }
      it { should belong_to(:volunteer_task) }
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

    it "requires a volunteer task" do
      rt = RequireTraining.new(training: create(:training))
      expect(rt).not_to be_valid
      expect(rt.errors[:volunteer_task]).to be_present
    end

    it "is not valid for a volunteer task id that does not exist" do
      rt = RequireTraining.new(training: create(:training), volunteer_task_id: 987_654_321)
      expect(rt).not_to be_valid
      expect { rt.save }.not_to change(RequireTraining, :count)
    end

    it "is refused by the database for a missing task even when validation is skipped" do
      rt = RequireTraining.new(training: create(:training), volunteer_task_id: 987_654_321)
      expect { rt.save!(validate: false) }.to raise_error(ActiveRecord::InvalidForeignKey)
    end

    it "is destroyed with its volunteer task" do
      rt = create(:require_training)
      expect { rt.volunteer_task.destroy }.to change(RequireTraining, :count).by(-1)
    end

    it "is destroyed with its training" do
      rt = create(:require_training)
      expect { rt.training.destroy }.to change(RequireTraining, :count).by(-1)
    end
  end
end

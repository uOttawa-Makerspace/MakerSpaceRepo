require "rails_helper"

RSpec.describe TrainingRequirement, type: :model do
  describe "Associations" do
    context "belongs_to" do
      it { should belong_to(:proficient_project).without_validating_presence }
      it { should belong_to(:training).without_validating_presence }
    end
  end
end

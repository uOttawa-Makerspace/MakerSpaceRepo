require "rails_helper"

RSpec.describe Category, type: :model do
  describe "Association" do
    context "belongs_to" do
      it { should belong_to(:repository).without_validating_presence }
      it { should belong_to(:category_option).without_validating_presence }
      it { should belong_to(:project_proposal).without_validating_presence }
    end
  end
end

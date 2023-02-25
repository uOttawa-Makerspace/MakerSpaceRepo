require "rails_helper"

RSpec.describe PrinterSession, type: :model do
  describe "Association" do
    context "belongs_to" do
      it { should belong_to(:printer).without_validating_presence }
      it { should belong_to(:user).without_validating_presence }
    end
  end
end

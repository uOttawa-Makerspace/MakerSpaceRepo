require "rails_helper"

RSpec.describe JobTaskQuote, type: :model do
  describe "Association" do
    context "belong_to" do
      it { should belong_to(:job_task) }
    end

    context "has_many" do
      it { should have_many(:job_task_quote_options) }
    end
  end
end

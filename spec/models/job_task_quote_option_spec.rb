require "rails_helper"

RSpec.describe JobTaskQuoteOption, type: :model do
  describe "Association" do
    context "belongs_to" do
      it { should belong_to(:job_task_quote).without_validating_presence }
      it { should belong_to(:job_option).without_validating_presence }
    end
  end

  describe "one price per option on a quote" do
    let(:quote) { create(:job_task_quote, job_task: create(:job_order).job_tasks.create!(title: "Task #1")) }
    let(:option) { create(:job_option) }

    before { described_class.create!(job_task_quote: quote, job_option: option, price: 5) }

    it "refuses a second row for the same quote and option" do
      duplicate = described_class.new(job_task_quote: quote, job_option: option, price: 7)

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:job_option_id]).to be_present
      expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
      expect(described_class.where(job_task_quote: quote, job_option: option).pluck(:price)).to eq([5])
    end

    it "allows the same option on another quote and another option on the same quote" do
      expect(described_class.new(job_task_quote: create(:job_task_quote, job_task: create(:job_order).job_tasks.create!(title: "Task #1")), job_option: option, price: 1)).to be_valid
      expect(described_class.new(job_task_quote: quote, job_option: create(:job_option), price: 1)).to be_valid
    end
  end
end

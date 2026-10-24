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

  describe "Validations" do
    it "keeps price at zero or above" do
      task = create(:job_order).job_tasks.create!(title: "Task #1")
      expect(build(:job_task_quote, job_task: task, price: -1)).not_to be_valid
      expect(build(:job_task_quote, job_task: task, price: 0)).to be_valid
    end

    # WART: service_price and service_quantity validations are commented out
    # (Design Services reuse); nothing stops non-numeric junk there.
    it "accepts anything for service_price/service_quantity (unvalidated — wart)" do
      task = create(:job_order).job_tasks.create!(title: "Task #1")
      quote = build(:job_task_quote, job_task: task, price: 1, service_price: 3, service_quantity: 2)
      expect(quote).to be_valid
    end
  end

  describe "#total_task_price" do
    it "adds the service line and the per-option prices" do
      task = create(:job_order).job_tasks.create!(title: "Task #1")
      quote = task.build_job_task_quote(price: 10, service_price: 3, service_quantity: 2)
      quote.save!
      option = JobOption.create!(name: "Expedited Resin", fee: 2)
      quote.job_task_quote_options.create!(job_option: option, price: 1.5)
      quote.job_task_quote_options.create!(job_option: JobOption.create!(name: "Polish", fee: 1), price: 0)
      expect(quote.reload.job_task_quote_options.sum(&:price)).to eq(1.5)
      expect(quote.total_task_price).to eq(17.5)
    end

    # WART: with a nil service_quantity (Design Services quotes) the math
    # raises; the callers rescue nothing.
    it "crashes when service_quantity is nil (wart)" do
      task = create(:job_order).job_tasks.create!(title: "Task #1")
      quote = task.build_job_task_quote(price: 10)
      quote.save!
      expect { quote.reload.total_task_price }.to raise_error(TypeError, /BigDecimal/)
    end
  end
end


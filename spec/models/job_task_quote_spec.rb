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

    it "keeps service_price and service_quantity at zero or above, or blank" do
      task = create(:job_order).job_tasks.create!(title: "Task #1")
      expect(build(:job_task_quote, job_task: task, price: 1, service_price: -3, service_quantity: 2)).not_to be_valid
      expect(build(:job_task_quote, job_task: task, price: 1, service_price: 3, service_quantity: -2)).not_to be_valid
      expect(build(:job_task_quote, job_task: task, price: 1, service_price: 3, service_quantity: 2)).to be_valid
      expect(build(:job_task_quote, job_task: task, price: 1, service_price: nil, service_quantity: nil)).to be_valid
    end
  end

  describe "#service_total" do
    it "multiplies the quantity by the price, counting a blank one as zero" do
      task = create(:job_order).job_tasks.create!(title: "Task #1")
      expect(task.build_job_task_quote(price: 10, service_price: 3, service_quantity: 2).service_total).to eq(6)
      expect(task.build_job_task_quote(price: 10, service_price: nil, service_quantity: 2).service_total).to eq(0)
    end
  end
end

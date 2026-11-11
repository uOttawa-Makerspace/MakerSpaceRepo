require "rails_helper"

RSpec.describe JobOrderStatus, type: :model do
  include JobOrderSpecHelpers

  describe "Association" do
    context "belongs_to" do
      it { should belong_to(:job_order).without_validating_presence }
      it { should belong_to(:job_status).without_validating_presence }
    end
  end

  describe "#acted_for_customer?" do
    let(:owner) { create(:user) }
    let(:staff) { create(:user, :staff) }
    let!(:order) { make_job_order!(owner: owner) }

    def row(status, user)
      order.job_order_statuses.create!(job_status: status, user: user || owner).tap { |r| r.update_columns(user_id: nil) unless user }
    end

    it "is true for an approval or a decline answered by someone other than the owner" do
      expect(row(JobStatus.waiting_processed, staff)).to be_acted_for_customer
      expect(row(JobStatus.declined, staff)).to be_acted_for_customer
    end

    it "is false when the owner answered" do
      expect(row(JobStatus.waiting_processed, owner)).not_to be_acted_for_customer
    end

    it "is false for other statuses, whoever acted" do
      expect(row(JobStatus.being_processed, staff)).not_to be_acted_for_customer
    end

    it "is false when no actor was recorded or the row has no order" do
      expect(row(JobStatus.waiting_processed, nil)).not_to be_acted_for_customer
      expect(JobOrderStatus.new(job_status: JobStatus.declined, user: staff)).not_to be_acted_for_customer
    end
  end
end

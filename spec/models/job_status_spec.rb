require "rails_helper"
require "open3"

RSpec.describe JobStatus, type: :model do
  describe "Association" do
    context "has_many" do
      it { should have_many(:job_order_statuses) }
    end
  end

  describe "Validations" do
    context "name" do
      subject { build :job_status }
      it { should validate_presence_of(:name) }
      it { should validate_uniqueness_of(:name) }
    end
  end

  describe "#t_name" do
    let(:status) { create(:job_status, name: "Draft", name_fr: "Brouillon") }

    it "returns the English name by default and the French name under the fr locale" do
      expect(status.t_name).to eq("Draft")
      I18n.with_locale(:fr) { expect(status.t_name).to eq("Brouillon") }
    end

    it "returns nil under fr when the French name is missing" do
      status.update!(name_fr: nil)
      I18n.with_locale(:fr) { expect(status.t_name).to be_nil }
    end
  end

  describe "workflow status lookups" do
    JobStatus::STATUS_NAMES.each do |key, name|
      describe ".#{key}" do
        it "returns the #{name.inspect} row" do
          row = create(:job_status, name: name)
          expect(JobStatus.public_send(key)).to eq(row)
        end

        it "raises JobStatus::Missing, naming the status, when the row is absent" do
          expect { JobStatus.public_send(key) }
            .to raise_error(JobStatus::Missing, /#{Regexp.escape(name)}/)
        end
      end
    end

    it "memoizes after the first successful lookup and forgets on reset_lookup_cache!" do
      row = create(:job_status, name: "Draft")
      expect(JobStatus.draft).to eq(JobStatus.draft)

      expect { JobStatus.where(id: row.id).delete_all }.not_to(change { JobStatus.draft })
      JobStatus.reset_lookup_cache!
      expect { JobStatus.draft }.to raise_error(JobStatus::Missing)
    end

    it "returns the same readonly record on every lookup" do
      row = create(:job_status, name: "Draft")
      first = JobStatus.draft

      expect(JobStatus.draft).to equal(first)
      expect(JobStatus.fetch(:draft)).to equal(first)
      expect(first).to eq(row)
      expect(first).to be_persisted.and be_readonly
      expect { first.save }.to raise_error(ActiveRecord::ReadOnlyRecord)
      expect { first.update(name_fr: "Brouillon") }.to raise_error(ActiveRecord::ReadOnlyRecord)
      expect(row.reload.name_fr).to be_nil
    end

    it "collects nothing from the status rows created with it (no inverse on JobOrderStatus#job_status)" do
      create(:job_status, name: "Draft")
      order = create(:job_order)
      3.times { order.job_order_statuses.create!(job_status: JobStatus.draft, user: order.user) }

      expect(JobOrderStatus.reflect_on_association(:job_status).options[:inverse_of]).to be(false)
      expect(JobStatus.draft.association(:job_order_statuses)).not_to be_loaded
      expect(JobStatus.draft.association(:job_order_statuses).target).to be_empty
    end

    it ".fetch raises KeyError for a key that is not a workflow status" do
      expect { JobStatus.fetch(:nope) }.to raise_error(KeyError)
      expect { JobStatus.fetch("draft") }.to raise_error(KeyError)
    end

    it "does not memoize a miss: the row created later is found" do
      expect { JobStatus.paid }.to raise_error(JobStatus::Missing)
      row = create(:job_status, name: "Paid (Waiting for Pick-Up)")
      expect(JobStatus.paid).to eq(row)
    end

    it "defines no constants" do
      expect(JobStatus.constants(false) - %i[STATUS_NAMES Missing LOOKUP_MUTEX]).to be_empty
    end
  end
end

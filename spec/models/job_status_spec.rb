require "rails_helper"
require "open3"

RSpec.describe JobStatus, type: :model do
  describe "Association" do
    # reference data: no association to the rows that use it; the foreign key refuses deleting a used status
    it "has no job_order_statuses association" do
      expect(JobStatus.reflect_on_all_associations).to be_empty
      expect(JobStatus.new).not_to respond_to(:job_order_statuses)
    end

    it "cannot be deleted while a job order status row uses it (foreign key)" do
      status = create(:job_status, name: "Draft")
      order = create(:job_order)
      order.job_order_statuses.create!(job_status: status, user: order.user)

      expect { JobStatus.where(id: status.id).delete_all }.to raise_error(ActiveRecord::InvalidForeignKey)
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

    it "returns the same frozen, readonly record on every lookup" do
      row = create(:job_status, name: "Draft")
      first = JobStatus.draft

      expect(JobStatus.draft).to equal(first)
      expect(JobStatus.fetch(:draft)).to equal(first)
      expect(first).to eq(row)
      expect(first).to be_persisted.and be_readonly.and be_frozen
      expect { first.save }.to raise_error(ActiveRecord::ReadOnlyRecord)
      expect(first.readonly?).to be(true)
    end

    it "returns the record another thread stored between this one's miss and its store" do
      create(:job_status, name: "Draft")
      stored = JobStatus.new(id: -1, name: "Draft").tap(&:readonly!).freeze # what the winning thread stored
      map = JobStatus.instance_variable_get(:@lookup_cache)
      allow(JobStatus).to receive(:find_by).and_wrap_original do |original, *args, **kwargs|
        map.put_if_absent(:draft, stored) # the other thread wins the race while this one loads
        original.call(*args, **kwargs)
      end

      expect(JobStatus.draft).to equal(stored)
      expect(JobStatus.draft).to equal(stored)
    end

    it "never returns nil when the cache is reset while the row loads" do
      row = create(:job_status, name: "Draft")
      allow(JobStatus).to receive(:find_by).and_wrap_original do |original, *args, **kwargs|
        JobStatus.reset_lookup_cache! # another thread resetting while this one loads
        original.call(*args, **kwargs)
      end

      expect(JobStatus.draft).to eq(row)
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

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

  # WART(D-J32): the constants are `JobStatus.find_by(name: ...)` evaluated in
  # the class body, so a process booted against a database without the
  # reference rows keeps nil for its whole lifetime. The suite stubs them per
  # example (spec/support/job_orders_spec_helpers.rb); this boots a REAL process
  # (the rows of this transactional example are uncommitted, as for any fresh
  # database).
  it "resolves its status constants once at boot: nil in a process booted without the rows" do
    create(:job_status, name: "Draft")
    out, status = Open3.capture2e(
      { "RAILS_ENV" => "test" },
      "bin/rails", "runner",
      'puts "CONSTANTS=" + [JobStatus::DRAFT, JobStatus::PAID, JobStatus::DECLINED].map(&:inspect).join(",")',
      chdir: Rails.root.to_s
    )
    expect(status).to be_success
    expect(out.lines.grep(/\ACONSTANTS=/).last.strip).to eq("CONSTANTS=nil,nil,nil")
  end
end

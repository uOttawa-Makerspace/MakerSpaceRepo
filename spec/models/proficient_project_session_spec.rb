require "rails_helper"

RSpec.describe ProficientProjectSession, type: :model do
  it { should belong_to(:certification) }

  it "refuses to be deleted while it holds a certification, and keeps the certification" do
    record = create(:proficient_project_session)
    cert = record.certification

    expect { record.destroy }.not_to change { [described_class.count, Certification.unscoped.count] }
    expect(record.errors.full_messages).to eq(["This session holds a certification, so it cannot be deleted."])
    expect(Certification.unscoped.exists?(cert.id)).to be(true)
  end
end

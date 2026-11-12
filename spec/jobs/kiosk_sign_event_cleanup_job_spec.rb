require "rails_helper"

RSpec.describe KioskSignEventCleanupJob do
  include ActiveSupport::Testing::TimeHelpers

  let(:staff) { create(:user, :staff) }
  let(:visitor) { create(:user, :regular_user) }
  let(:space) { create(:space) }

  def log_at(time) = KioskSignEvent.create!(actor: staff, visitor: visitor, space: space, action: "sign_in", created_at: time)

  it "deletes only rows older than one year, and is safe to run twice" do
    freeze_time do
      old = log_at(1.year.ago - 1.day)
      edge = log_at(1.year.ago + 1.minute)
      recent = log_at(1.day.ago)

      described_class.perform_now
      expect(KioskSignEvent.pluck(:id)).to contain_exactly(edge.id, recent.id)
      expect(KioskSignEvent.exists?(old.id)).to be(false)

      expect { described_class.perform_now }.not_to change(KioskSignEvent, :count)
    end
  end

  it "works through more rows than one batch" do
    freeze_time do
      3.times { log_at(2.years.ago) }
      log_at(1.day.ago)
      expect(KioskSignEvent.purge_old!(batch_size: 2)).to eq(3)
      expect(KioskSignEvent.count).to eq(1)
    end
  end
end

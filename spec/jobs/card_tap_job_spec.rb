require "rails_helper"

RSpec.describe CardTapJob, type: :job do
  include_context "with test cable adapter"

  let(:space) { create(:space) }
  let(:user) { create(:user, :regular_user) }
  let(:rfid) { create(:rfid, user: user) }

  it "is queued on the default queue" do
    expect(described_class.new.queue_name).to eq("default")
  end

  it "is limited to one concurrent run per space for a minute" do
    expect(described_class.concurrency_limit).to eq(1)
    expect(described_class.concurrency_duration).to eq(1.minute)
    expect(described_class.concurrency_key.call(rfid, 42)).to eq(42)
  end

  it "sends the table update on the signed-in table stream" do
    expect { described_class.perform_now(rfid, space.id) }.to have_broadcasted_to(StaffDashboardChannel.table_stream(space.id, :en)).from_channel(Turbo::StreamsChannel)
  end

  it "queues the membership check for the same card and space, and sends no popup itself" do
    expect { described_class.perform_now(rfid, space.id) }
      .to have_enqueued_job(MembershipCheckJob).with(rfid, space.id)
      .and not_have_broadcasted_to("space_event_#{space.id}")
  end
end

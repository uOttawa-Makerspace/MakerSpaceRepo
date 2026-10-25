require "rails_helper"

RSpec.describe CardTapJob, type: :job do
  include_context "with test cable adapter"

  let(:space) { create(:space) }
  let(:user) { create(:user, :regular_user) }
  let(:rfid) { create(:rfid, user: user) }

  before do
    create(:membership_tier, title_en: "Faculty membership", title_fr: "Adhesion de la faculte", internal_price: 0, external_price: 0, duration: 4.months.to_i)
  end

  it "is queued on the default queue" do
    expect(described_class.new.queue_name).to eq("default")
  end

  it "is limited to one concurrent run per space for a minute" do
    expect(described_class.concurrency_limit).to eq(1)
    expect(described_class.concurrency_duration).to eq(1.minute)
    expect(described_class.concurrency_key.call(rfid, 42)).to eq(42)
  end

  it "validates the uOEng membership for the card owner in the tapped space" do
    expect(user).to receive(:validate_uoeng_membership).with(card_number: rfid.card_number, space: space)
    allow(rfid).to receive(:user).and_return(user)
    described_class.perform_now(rfid, space.id)
  end

  it "pushes the add_user modal to the space event stream" do
    expect { described_class.perform_now(rfid, space.id) }.to have_broadcasted_to("space_event_#{space.id}").with(a_hash_including("add_user"))
  end

  it "sends a table update on the signed-in table stream too" do
    expect { described_class.perform_now(rfid, space.id) }.to have_broadcasted_to("signed_in_table_space_#{space.id}").from_channel(Turbo::StreamsChannel)
  end

  it "logs an error row and re-raises when the membership check fails" do
    allow_any_instance_of(User).to receive(:validate_uoeng_membership).and_raise(RuntimeError, "uoeng down")
    expect { described_class.perform_now(rfid, space.id) }.to raise_error(RuntimeError, "uoeng down").and change { TapBoxLog.where(event_type: "error").count }.by(1)
    expect(TapBoxLog.where(event_type: "error").last).to have_attributes(user_id: user.id, space_id: space.id, card_number: rfid.card_number)
  end
end

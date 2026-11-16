require "rails_helper"

RSpec.describe MembershipCheckJob, type: :job do
  include ActiveJob::TestHelper
  include_context "with test cable adapter"

  let(:space) { create(:space) }
  let(:user) { create(:user, :regular_user) }
  let(:rfid) { create(:rfid, user: user) }
  let(:popup_stream) { "space_event_#{space.id}" }

  before do
    create(:membership_tier, title_en: "Faculty membership", title_fr: "Adhesion de la faculte", internal_price: 0, external_price: 0, duration: 4.months.to_i)
  end

  def stub_checks(*answers)
    calls = 0
    allow_any_instance_of(User).to receive(:validate_uoeng_membership) do
      answer = answers[[calls, answers.size - 1].min]
      calls += 1
      answer
    end
  end

  def popups
    ActionCable.server.pubsub.broadcasts(popup_stream)
  end

  it "is queued on the default queue and runs one check per user at a time" do
    expect(described_class.new.queue_name).to eq("default")
    expect(described_class.concurrency_limit).to eq(1)
    expect(described_class.concurrency_key.call(rfid, space.id)).to eq(user.id)
  end

  it "validates the membership for the card owner in the tapped space" do
    expect(user).to receive(:validate_uoeng_membership).with(card_number: rfid.card_number, space: space)
    allow(rfid).to receive(:user).and_return(user)
    described_class.perform_now(rfid, space.id)
  end

  it "pushes the add_user popup after the check" do
    expect { described_class.perform_now(rfid, space.id) }.to have_broadcasted_to(popup_stream).with(a_hash_including("add_user"))
  end

  it "reports the membership granted by the check in the popup" do
    user.update!(faculty: "Engineering")
    described_class.perform_now(rfid, space.id)
    expect(Membership.where(user: user).count).to eq(1)
    expect(JSON.parse(popups.last)["add_user"]["membership"]).to be(true)
  end

  it "does not duplicate a membership when the check runs twice" do
    user.update!(faculty: "Engineering")
    2.times { described_class.perform_now(rfid, space.id) }
    expect(Membership.where(user: user).count).to eq(1)
  end

  it "revokes a faculty membership once when the check runs twice for a non-engineering user" do
    tier = MembershipTier.find_by!(title_en: "Faculty membership")
    create(:membership, user: user, membership_tier: tier, status: "paid", start_date: 1.day.ago, end_date: 1.month.from_now)
    expect { 2.times { described_class.perform_now(rfid, space.id) } }
      .to change { TapBoxLog.where(event_type: TapBoxLog::MEMBERSHIP_CHECK).count }.by(1)
    expect(Membership.where(user: user).pluck(:status)).to eq(["revoked"])
  end

  it "retries a transient failure, ends with the membership granted and sends the popup once" do
    user.update!(faculty: "Engineering")
    allow(Rails.env).to receive(:test?).and_return(false)
    allow(Rails.application.credentials).to receive(:dig).and_call_original
    allow(Rails.application.credentials).to receive(:dig).with(:test, :uoeng).and_return(query_by_id: "https://uoeng.example.test/by_id/", student_information_key: "k")
    user.update!(student_id: "300000009")
    stub_request(:get, %r{uoeng.example.test})
      .to_timeout.then
      .to_return(status: 503, body: "").then
      .to_return(status: 200, body: { "student_this_semester" => true, "faculty" => "GENIE" }.to_json)

    perform_enqueued_jobs { described_class.perform_later(rfid, space.id) }

    expect(Membership.where(user: user, status: "paid").count).to eq(1)
    expect(popups.size).to eq(1)
    expect(JSON.parse(popups.first)["add_user"]["membership"]).to be(true)
  end

  it "schedules a retry and sends no popup after a failed attempt" do
    stub_checks(:unavailable)
    expect { described_class.perform_now(rfid, space.id) }.to have_enqueued_job(described_class).with(rfid, space.id)
    expect(popups).to be_empty
  end

  it "stops after five attempts, logs the failure and sends the popup once" do
    stub_checks(:unavailable)
    perform_enqueued_jobs { described_class.perform_later(rfid, space.id) }

    expect(popups.size).to eq(1)
    expect(TapBoxLog.where(event_type: TapBoxLog::ERROR, user_id: user.id).count).to eq(1)
  end

  it "does not retry when the upstream gave an answer that cannot be used" do
    stub_checks(:unknown)
    expect { described_class.perform_now(rfid, space.id) }
      .to have_broadcasted_to(popup_stream).and not_have_enqueued_job(described_class)
    expect(TapBoxLog.where(event_type: TapBoxLog::ERROR)).to be_empty
  end

  it "does not retry when the user is not engineering" do
    allow(Rails.env).to receive(:test?).and_return(false)
    allow(Rails.application.credentials).to receive(:dig).and_call_original
    allow(Rails.application.credentials).to receive(:dig).with(:test, :uoeng).and_return(query_by_id: "https://uoeng.example.test/by_id/", student_information_key: "k")
    user.update!(student_id: "300000009")
    request = stub_request(:get, %r{uoeng.example.test}).to_return(status: 200, body: { "student_this_semester" => true, "faculty" => "ARTS" }.to_json)

    perform_enqueued_jobs { described_class.perform_later(rfid, space.id) }

    expect(request).to have_been_requested.once
    expect(popups.size).to eq(1)
  end

  it "logs an error row but still sends the popup when the Faculty membership tier is missing" do
    MembershipTier.where(title_en: "Faculty membership").destroy_all
    expect { described_class.perform_now(rfid, space.id) }
      .to have_broadcasted_to(popup_stream).with(a_hash_including("add_user"))
      .and change { TapBoxLog.where(event_type: "error").count }.by(1)
  end

  it "logs an error row and re-raises an unexpected failure, without a popup" do
    allow_any_instance_of(User).to receive(:validate_uoeng_membership).and_raise(RuntimeError, "boom")
    expect { described_class.perform_now(rfid, space.id) }.to raise_error(RuntimeError, "boom").and change { TapBoxLog.where(event_type: "error").count }.by(1)
    expect(popups).to be_empty
  end

  it "is discarded without an error row or a popup when the card was deleted while it waited" do
    data = described_class.new(rfid, space.id).serialize
    rfid.destroy!
    expect { ActiveJob::Base.execute(data) }.not_to raise_error
    expect(TapBoxLog.where(event_type: TapBoxLog::ERROR)).to be_empty
    expect(popups).to be_empty
  end
end

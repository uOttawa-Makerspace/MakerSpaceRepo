# frozen_string_literal: true

require "rails_helper"

# A mail queued with deliver_later whose record was deleted before the job ran has nothing left to say: the job
# is dropped instead of failing.
RSpec.describe ApplicationMailDeliveryJob, type: :job do
  before do
    ActionMailer::Base.deliveries.clear
  end

  let(:order) { create(:job_order) }
  let(:sender) { create(:user, :staff) }
  let(:recipient) { create(:user, :regular_user) }
  let(:chat_message) { ChatMessage.create!(job_order: order, sender: sender, message: "Hello") }

  it "delivers a queued chat notification while its message still exists" do
    ChatMessageMailer.new_message(chat_message, recipient.email).deliver_later

    perform_enqueued_jobs

    expect(ActionMailer::Base.deliveries.map(&:to)).to eq([[recipient.email]])
  end

  it "drops the delivery without failing when the message was deleted before the job ran" do
    ChatMessageMailer.new_message(chat_message, recipient.email).deliver_later
    chat_message.destroy!

    expect { perform_enqueued_jobs }.not_to raise_error

    expect(ActionMailer::Base.deliveries).to be_empty
  end

  it "still raises for an error that is not a missing record" do
    ChatMessageMailer.new_message(chat_message, recipient.email).deliver_later
    allow_any_instance_of(ChatMessageMailer).to receive(:mail).and_raise(ArgumentError, "boom")

    expect { perform_enqueued_jobs }.to raise_error(ArgumentError, "boom")
  end
end

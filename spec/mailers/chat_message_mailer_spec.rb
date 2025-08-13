require "rails_helper"

RSpec.describe ChatMessageMailer, type: :mailer do
  describe ".new_message" do
    let(:job_order) { create(:job_order) }
    let(:sender) { create(:user) }
    let(:recipient1) { create(:user) }
    let(:recipient2) { create(:user) }

    let(:chat_message) do
      ChatMessage.create!(
        job_order: job_order,
        sender: sender,
        message: "Hello, this is a test message"
      )
    end

    let(:mail) { described_class.new_message(chat_message, [recipient1, recipient2]) }

    it "renders the subject" do
      expect(mail.subject).to eq("MakerRepo - Nouveau message // New message")
    end

    it "sends to the recipients' emails" do
      expect(mail.to).to match_array([recipient1.email, recipient2.email])
    end

    it "assigns @chat_message in the mailer view" do
      expect(mail.body.encoded).to include("Hello, this is a test message")
    end

    it "assigns @job_order in the mailer view" do
      expect(mail.body.encoded).to include(job_order.title) if job_order.respond_to?(:title)
    end

    it "assigns @sender in the mailer view" do
      expect(mail.body.encoded).to include(sender.name) if sender.respond_to?(:name)
    end
  end
end

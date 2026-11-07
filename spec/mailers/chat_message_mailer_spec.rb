require "rails_helper"

RSpec.describe ChatMessageMailer, type: :mailer do
  describe ".new_message" do
    before { create(:job_status, name: "Draft") } # ChatMessage#schedule_notification_email reads JobStatus.draft

    let(:job_order) { create(:job_order) }
    let(:sender) { create(:user) }
    let(:recipient1) { create(:user) }

    let(:chat_message) do
      ChatMessage.create!(
        job_order: job_order,
        sender: sender,
        message: "Hello, this is a test message"
      )
    end

    let(:mail) { described_class.new_message(chat_message, recipient1.email) }

    it "renders the subject" do
      expect(mail.subject).to eq("MakerRepo - Nouveau message // New message")
    end

    it "sends to the one recipient only" do
      expect(mail.to).to eq([recipient1.email])
      expect(mail.header[:bcc]).to be_nil
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

    describe "when the sender's account was deleted before delivery" do
      before do
        chat_message
        sender.soft_delete!
      end

      it "still delivers, naming the sender neutrally in both languages" do
        body = described_class.new_message(chat_message.reload, recipient1.email).body.encoded
        expect(body).to include("from Deleted user")
        expect(body).to include("de la part de Utilisateur supprimé")
        expect(body).not_to include(sender.name)
      end
    end
  end
end

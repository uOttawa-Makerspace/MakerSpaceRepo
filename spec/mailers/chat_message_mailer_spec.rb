require "rails_helper"

RSpec.describe ChatMessageMailer, type: :mailer do
  describe "new_message" do
    let(:mail) { ChatMessageMailer.new_message }

    it "renders the headers" do
      expect(mail.subject).to eq("New message")
      expect(mail.to).to eq(["to@example.org"])
      expect(mail.from).to eq(["from@example.com"])
    end

    it "renders the body" do
      expect(mail.body.encoded).to match("Hi")
    end
  end

end

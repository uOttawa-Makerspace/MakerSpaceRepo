# frozen_string_literal: true

require "rails_helper"

RSpec.describe KeyRequestMailer, type: :mailer do
  let(:requester) { create(:user, :staff, name: "Pat Requester") }
  let(:key_request) do
    create(:key_request, :status_waiting_for_approval, :all_questions_answered,
           user: requester, supervisor: create(:user, :admin), space: create(:space))
  end

  # The mail's visible text, with markup and entities resolved.
  def text_of(mail)
    Nokogiri::HTML(mail.body.decoded).text.squish
  end

  describe ".send_key_request_denied" do
    it "tells the requester in French and English that the request was denied, and why" do
      key_request.deny("Supervisor must be a professor")
      mail = described_class.send_key_request_denied(key_request.id, "Supervisor must be a professor")
      mail.deliver_now

      expect(mail.to).to eq([requester.email])
      expect(mail.subject).to eq("MakerRepo - Demande de clé refusée // Key request denied")
      body = text_of(mail)
      expect(body).to include("Bonjour Pat Requester,", "Hello Pat Requester,")
      expect(body).to include("Votre demande de clé a été examinée et refusée par un administrateur.")
      expect(body).to include("Your key request has been reviewed and denied by an admin.")
      expect(body).to include("Raison donnée :", "Reason given:", "Supervisor must be a professor")
      expect(body.index("Bonjour")).to be < body.index("Hello")
      expect(mail.body.decoded).to include("/key_requests/#{key_request.id}")
    end

    it "has no reason line when no reason was given" do
      key_request.deny("")
      mail = described_class.send_key_request_denied(key_request.id, nil)
      body = text_of(mail)
      expect(body).not_to include("Reason given:")
      expect(body).not_to include("Raison donnée")
    end

    it "shows the reason as text, never as markup" do
      key_request.deny("<b>no</b> & <script>x</script>")
      body = described_class.send_key_request_denied(key_request.id, "<b>no</b> & <script>x</script>").body.decoded
      expect(body).to include("&lt;b&gt;no&lt;/b&gt; &amp; &lt;script&gt;x&lt;/script&gt;")
      expect(body).not_to include("<script>x")
    end

    it "still says what the admin wrote when the request is resubmitted before delivery" do
      key_request.deny("Supervisor must be a professor")
      mail = described_class.send_key_request_denied(key_request.id, key_request.denial_reason)
      key_request.submit
      expect(key_request.reload.denial_reason).to be_nil
      expect(text_of(mail)).to include("Supervisor must be a professor")
    end

    it "sends nothing when the requester has no email" do
      key_request.deny("No")
      requester.update_columns(email: "")
      expect { described_class.send_key_request_denied(key_request.id, "No").deliver_now }
        .not_to change { ActionMailer::Base.deliveries.size }
    end

    it "sends nothing when the requester's account was deleted" do
      key_request.deny("No")
      allow_any_instance_of(User).to receive(:deleted?).and_return(true)
      expect { described_class.send_key_request_denied(key_request.id, "No").deliver_now }
        .not_to change { ActionMailer::Base.deliveries.size }
    end
  end
end

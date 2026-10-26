# frozen_string_literal: true

require "rails_helper"

# FIXED(D-API01): the React app's Help form calls `PUT /send_email` (JSON, Bearer
# token). It used to fall through to `PUT /:username` -> users#update and overwrite
# the caller's own name/email without sending any mail.
RSpec.describe "PUT /send_email (React Help form)", type: :request do
  let(:user) { create(:user, :regular_user, name: "Original Name", email: "original@example.com") }
  let(:headers) { { "Authorization" => "Bearer #{user.token}" } }
  let(:payload) do
    {
      name: "Help Seeker",
      email: "seeker@example.com",
      subject: "Printer will not start",
      comments: "It beeps three times and stops.",
      app_version: "2.4.1"
    }
  end

  before { block_external_http! }

  def deliveries
    ActionMailer::Base.deliveries
  end

  it "sends the support email and never touches the signed-in user" do
    expect do
      perform_enqueued_jobs { put "/send_email", params: payload.to_json, headers: headers.merge("Content-Type" => "application/json", "Accept" => "application/json") }
    end.to change { deliveries.size }.by(1)

    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)).to eq("status" => "sent")
    mail = deliveries.last
    expect(mail.to).to eq(["seeker@example.com"])
    expect(mail.bcc).to include("uottawa.makerepo@gmail.com")
    expect(mail.subject).to eq("Issue Report | Printer will not start")
    expect(mail.body.encoded).to include("It beeps three times", "2.4.1")

    user.reload
    expect(user.name).to eq("Original Name")
    expect(user.email).to eq("original@example.com")
  end

  it "rejects invalid input with 422 JSON errors and sends nothing" do
    expect do
      perform_enqueued_jobs { put "/send_email", params: payload.merge(subject: "short", email: "nope").to_json, headers: headers.merge("Content-Type" => "application/json") }
    end.not_to(change { deliveries.size })

    expect(response).to have_http_status(:unprocessable_content)
    expect(JSON.parse(response.body)["errors"].join).to include("Subject", "Email")
    expect(user.reload.name).to eq("Original Name")
  end

  it "refuses anonymous callers with 401 and sends nothing" do
    expect do
      perform_enqueued_jobs { put "/send_email", params: payload.to_json, headers: { "Content-Type" => "application/json" } }
    end.not_to(change { deliveries.size })
    expect(response).to have_http_status(:unauthorized)
  end

  describe "regression: PUT /:username still updates the real profile" do
    it "updates the profile for the owner" do
      put user_path(user.username),
          params: { user: { name: "Renamed Person" } }.to_json,
          headers: headers.merge("Content-Type" => "application/json")
      expect(user.reload.name).to eq("Renamed Person")
    end
  end
end

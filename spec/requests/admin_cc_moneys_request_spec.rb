# frozen_string_literal: true

require "rails_helper"

# Admin::CcMoneysController (list of unlinked CC money) and Admin::CcMoneyClaimEmailsController
# (resend of the claim mail). Admin only, like the rest of the admin area.

RSpec.describe "Admin CC money claim email", type: :request do
  include SpacesSpecHelpers

  let!(:unlinked) { create(:cc_money, user: nil, linked: false, cc: 30) }
  let!(:linked) { create(:cc_money, cc: 10) }
  let(:buyer) { "buyer@example.com" }

  def resend(row = unlinked, email: buyer)
    post admin_cc_money_claim_email_path(row), params: { email: email }
  end

  # The claim token carried by a delivered claim mail.
  def mailed_token(mail)
    CGI.unescape(mail.body.decoded[/link_cc_to_user\?token=([^"&\s<]+)/, 1])
  end

  def mails
    perform_enqueued_jobs
    ActionMailer::Base.deliveries
  end

  describe "role matrix" do
    let(:calls) do
      {
        index: -> { get admin_cc_moneys_path },
        resend: -> { resend }
      }
    end

    %i[guest regular staff].each do |role|
      it "bounces #{role} without sending mail" do
        expect_bounced(role, calls, state: -> { [CcMoney.order(:id).map(&:attributes), enqueued_jobs.size] })
        expect(mails).to be_empty
      end
    end
  end

  context "as admin" do
    let!(:admin) { sign_in_as(:admin) }

    it "lists only unlinked rows, each with a resend form" do
      get admin_cc_moneys_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(admin_cc_money_claim_email_path(unlinked))
      expect(response.body).not_to include(admin_cc_money_claim_email_path(linked))
    end

    it "delivers the claim mail with the same link format as the shop order mail" do
      resend
      expect(response).to redirect_to(admin_cc_moneys_path)
      mail = mails.last
      expect(mail.to).to eq([buyer])
      expect(mail.subject).to eq("Your CC Money order")
      expect(mail.body.decoded).to include("/cc_moneys/link_cc_to_user?token=")
      expect(CcMoney.verified_claim_token(mailed_token(mail))).to eq([unlinked.id, 1])
      expect(mail.body.decoded).to include("30 CCs")
      expect(flash[:notice]).to include(buyer)
    end

    it "records the buyer's address when none is stored and makes the new link the only valid one" do
      old = unlinked.claim_token
      resend(unlinked, email: "Buyer@Example.com")
      unlinked.reload
      expect(unlinked.purchaser_email).to eq("buyer@example.com")
      expect(unlinked.claim_token_generation).to eq(1)
      expect(unlinked.claim_generation?(CcMoney.verified_claim_token(old).last)).to be(false)
      expect(CcMoney.verified_claim_token(mailed_token(mails.last))).to eq([unlinked.id, 1])
    end

    it "refuses an address other than the recorded buyer's and sends nothing" do
      unlinked.update!(purchaser_email: "first@example.com")
      resend(unlinked, email: "someone.else@example.com")
      expect(flash[:alert]).to eq(I18n.t("errors.admin.cc_money_claim_email.email_mismatch"))
      expect(unlinked.reload.claim_token_generation).to eq(0)
      expect(mails).to be_empty
    end

    it "sends again to the recorded address and keeps the stored address" do
      unlinked.update!(purchaser_email: "first@example.com")
      resend(unlinked, email: "First@Example.com")
      expect(mails.last.to).to eq(["First@Example.com"])
      expect(unlinked.reload.purchaser_email).to eq("first@example.com")
      expect(unlinked.claim_token_generation).to eq(1)
    end

    it "logs who resent it" do
      allow(Rails.logger).to receive(:info)
      resend
      expect(Rails.logger).to have_received(:info).with(/CC claim email for cc_money #{unlinked.id} resent to #{buyer} by user #{admin.id}/)
    end

    it "refuses a row already linked to an account" do
      resend(linked)
      expect(response).to redirect_to(admin_cc_moneys_path)
      expect(flash[:alert]).to eq(I18n.t("errors.admin.cc_money_claim_email.already_linked"))
      expect(mails).to be_empty
    end

    it "refuses a missing or malformed address" do
      resend(unlinked, email: "not-an-address")
      expect(flash[:alert]).to eq(I18n.t("errors.admin.cc_money_claim_email.email_invalid"))
      expect(mails).to be_empty
    end

    it "answers 404 for an unknown row" do
      post admin_cc_money_claim_email_path(0), params: { email: buyer }
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "CcMoney#claimable?" do
    it "is true only for an unlinked row" do
      expect(unlinked).to be_claimable
      expect(linked).not_to be_claimable
    end
  end
end

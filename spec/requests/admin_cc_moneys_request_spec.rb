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
      token = Rails.application.message_verifier(:cc).generate(unlinked.id)
      expect(mail.body.decoded).to include("/cc_moneys/link_cc_to_user?token=#{CGI.escape(token)}")
      expect(mail.body.decoded).to include("30 CCs")
      expect(flash[:notice]).to include(buyer)
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

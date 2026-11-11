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

  def correct(row = unlinked, email: "right@example.com")
    patch admin_cc_money_purchase_email_path(row), params: { email: email }
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
        resend: -> { resend },
        correct: -> { correct }
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
      expect(CcMoney.for_claim_token(mailed_token(mail))).to eq(unlinked)
      expect(mail.body.decoded).to include("30 CCs")
      expect(flash[:notice]).to include(buyer)
    end

    it "records the buyer's address when none is stored and makes the new link the only valid one" do
      old = unlinked.claim_token
      resend(unlinked, email: "Buyer@Example.com")
      unlinked.reload
      expect(unlinked.purchaser_email).to eq("buyer@example.com")
      expect(unlinked.claim_token_generation).to eq(1)
      expect(CcMoney.for_claim_token(old)).to be_nil
      expect(CcMoney.for_claim_token(mailed_token(mails.last))).to eq(unlinked)
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

  describe "correcting the purchase email" do
    let!(:typo_row) { create(:cc_money, user: nil, linked: false, cc: 20, purchaser_email: "typo@example.com") }
    let(:right) { create(:user, :regular_user) }

    context "as admin" do
      let!(:admin) { sign_in_as(:admin) }

      it "writes the address, records the correction and mails the new address once, and only the new link works" do
        old = typo_row.claim_token
        correct(typo_row, email: right.email.upcase)
        expect(response).to redirect_to(admin_cc_moneys_path)
        expect(flash[:notice]).to include(right.email)
        typo_row.reload
        expect(typo_row.purchaser_email).to eq(right.email)
        expect(typo_row.email_corrections.sole).to have_attributes(admin: admin, old_email: "typo@example.com", new_email: right.email)
        delivered = mails.select { |m| m.to == [right.email] }
        expect(delivered.size).to eq(1)
        expect(mails.size).to eq(1)
        expect(CcMoney.for_claim_token(old)).to be_nil
        expect(CcMoney.for_claim_token(mailed_token(delivered.first))).to eq(typo_row)
        expect(typo_row.claimable_by?(right)).to be(true)
      end

      it "shows the latest correction on the row" do
        correct(typo_row, email: "first@example.com")
        correct(typo_row, email: "second@example.com")
        get admin_cc_moneys_path
        expect(response.body).to include("first@example.com to second@example.com by #{admin.username}")
        expect(response.body).to include(admin_cc_money_purchase_email_path(typo_row))
      end

      it "refuses a claimed row, an invalid address and an unchanged address with a message and no mail or change" do
        correct(linked)
        expect(flash[:alert]).to eq(I18n.t("errors.admin.cc_money_purchase_email.already_linked"))
        correct(typo_row, email: "nope")
        expect(flash[:alert]).to eq(I18n.t("errors.admin.cc_money_purchase_email.email_invalid"))
        correct(typo_row, email: "Typo@example.com")
        expect(flash[:alert]).to eq(I18n.t("errors.admin.cc_money_purchase_email.email_unchanged"))
        expect(typo_row.reload).to have_attributes(purchaser_email: "typo@example.com", claim_token_generation: 0)
        expect(CcMoneyEmailCorrection.count).to eq(0)
        expect(mails).to be_empty
      end

      it "has a message for every outcome in English and French" do
        %i[already_linked email_invalid email_unchanged].each do |outcome|
          %i[en fr].each do |locale|
            expect(I18n.t("errors.admin.cc_money_purchase_email.#{outcome}", locale: locale, raise: true)).to be_present
          end
        end
        %i[en fr].each { |locale| expect(I18n.t("admin.cc_money_purchase_email.corrected", locale: locale, cc: 1, email: "a@b.c")).to include("a@b.c") }
      end

      it "answers 404 for an unknown row" do
        correct(CcMoney.new(id: 0))
        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe "CcMoney#unclaimed?" do
    it "is true only for an unlinked row" do
      expect(unlinked).to be_unclaimed
      expect(linked).not_to be_unclaimed
    end
  end
end

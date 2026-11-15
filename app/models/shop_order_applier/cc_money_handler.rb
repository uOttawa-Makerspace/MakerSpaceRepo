# frozen_string_literal: true

class ShopOrderApplier
  # The CC Money an order buys: one CC row per CC product line item, 10 CC per unit. A buyer who is not a user gets
  # an unlinked row and the claim mail, queued after the commit.
  class CcMoneyHandler < Handler
    def call
      if email.blank?
        applier.report_unresolved(plan, UnresolvedCcOrder, "CC", "has the CC product but no customer email")
        return
      end

      user = User.find_by(email: email)
      Payments::ShopifyAdapter::Order.cc_items(hook).each do |item|
        cc = 10 * item["quantity"].to_i
        user.present? ? CcMoney.create!(user_id: user.id, cc: cc) : credit_unclaimed(cc)
      end
    end

    private

    def credit_unclaimed(cc)
      token = CcMoney.create!(cc: cc, linked: false, purchaser_email: email).claim_token
      address = email
      applier.after_commit("cc_claim_mail") { MsrMailer.send_cc_money_email(address, cc, token).deliver_later }
    end
  end
end

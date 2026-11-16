# frozen_string_literal: true

# CC Money bought without an account that nobody has claimed yet.
class Admin::CcMoneysController < AdminAreaController
  layout "admin_area"

  def index
    @cc_moneys = CcMoney.unclaimed
                        .includes(latest_email_correction: :admin, latest_claim_email_resend: :admin)
                        .order(created_at: :desc)
  end
end

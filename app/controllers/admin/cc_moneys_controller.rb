# frozen_string_literal: true

# CC Money bought without an account that nobody has claimed yet.
class Admin::CcMoneysController < AdminAreaController
  layout "admin_area"

  def index
    @cc_moneys = CcMoney.unlinked.order(created_at: :desc)
  end
end

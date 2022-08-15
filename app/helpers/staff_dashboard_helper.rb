# frozen_string_literal: true

module StaffDashboardHelper
  def return_no_waiver_id(user)
    user.read_and_accepted_waiver_form ? id = "" : id = "no-waiver"
    id
  end
end

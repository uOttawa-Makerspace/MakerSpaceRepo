# frozen_string_literal: true

# A staff member runs the faculty membership check for one user from that
# user's profile, for people without a working card. It is the same check a
# card tap runs, with the same outcomes, including ending an active faculty
# membership of someone who is no longer eligible.
class MembershipChecksController < ApplicationController
  before_action :signed_in

  # Each check asks the uOEng service, so it is limited per staff member and per
  # checked user.
  RATE_LIMITED = -> { redirect_to user_path(params[:user_username]), alert: t("membership_checks.rate_limited") }
  rate_limit to: 10, within: 1.minute, only: :create, name: "staff",
             by: -> { current_user.id }, with: RATE_LIMITED
  rate_limit to: 3, within: 1.minute, only: :create, name: "user",
             by: -> { params[:user_username].to_s.downcase }, with: RATE_LIMITED

  def create
    user = User.find_by_username!(params[:user_username])
    authorize!(user, :membership_checkable_by?)
    return if performed?

    result = user.validate_uoeng_membership(space: current_user.space)
    redirect_to user_path(user.username), flash: flash_for(result)
  end

  private

  # A granted membership is a Membership; nil means the user is not eligible; a
  # symbol means the upstream gave no answer.
  def flash_for(result)
    case result
    when Membership then { notice: t("membership_checks.granted") }
    when nil then { alert_yellow: t("membership_checks.not_eligible") }
    else { alert: t("membership_checks.unavailable") }
    end
  end
end

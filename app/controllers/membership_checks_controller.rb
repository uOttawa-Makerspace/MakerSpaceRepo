# frozen_string_literal: true

# A staff member runs the faculty membership check for one user from that
# user's profile, for people without a working card. It is the same check a
# card tap runs, with the same outcomes, including ending an active faculty
# membership of someone who is no longer eligible.
class MembershipChecksController < ApplicationController
  before_action :signed_in
  # Before the rate limits, so a request from someone who may not run the check
  # never uses up a quota.
  before_action :load_user_and_authorize

  # Each check asks the uOEng service, so it is limited per staff member and per
  # checked user.
  RATE_LIMITED = -> { redirect_to user_path(@checked_user.username), alert: t("membership_checks.rate_limited") }
  rate_limit to: 10, within: 1.minute, only: :create, name: "staff",
             by: -> { current_user.id }, with: RATE_LIMITED
  rate_limit to: 3, within: 1.minute, only: :create, name: "user",
             by: -> { "user:#{@checked_user.id}" }, with: RATE_LIMITED

  def create
    redirect_to user_path(@checked_user.username), flash: run_check
  end

  private

  def load_user_and_authorize
    @checked_user = User.find_by_username!(params[:user_username])
    authorize!(@checked_user, :membership_checkable_by?)
  end

  # Nothing is asked of uOEng for a user it cannot look up.
  def run_check
    return { alert: t("membership_checks.not_queryable") } unless @checked_user.uoeng_queryable?

    ended = @checked_user.active_faculty_membership_count
    flash_for(@checked_user.validate_uoeng_membership(space: current_user.space), ended)
  end

  # A granted membership is a Membership; nil means the user is not eligible; a
  # symbol means the upstream gave no answer.
  def flash_for(result, ended)
    case result
    when Membership then { notice: t("membership_checks.granted") }
    when :mismatch then { alert: t("membership_checks.identity_mismatch") }
    when nil then { alert_yellow: t(ended.positive? ? "membership_checks.not_eligible_ended" : "membership_checks.not_eligible") }
    else { alert: t("membership_checks.unavailable") }
    end
  end
end

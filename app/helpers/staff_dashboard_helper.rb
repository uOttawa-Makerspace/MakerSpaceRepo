# frozen_string_literal: true

module StaffDashboardHelper
  def return_no_waiver_id(user)
    user.read_and_accepted_waiver_form ? id = "" : id = "no-waiver"
    id
  end

  # "3 days ago at Space Name": the end of the previous visit and the space of the user's
  # newest session. Blank for a first visit. Preload :lab_sessions and
  # latest_lab_session: :space where many users are listed.
  def previous_visit_text(user)
    ended_at = user.previous_visit_ended_at
    return if ended_at.nil?

    "#{time_ago_in_words(ended_at)} ago at #{user.latest_lab_session.space.name}"
  end
end

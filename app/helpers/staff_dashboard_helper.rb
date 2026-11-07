# frozen_string_literal: true

module StaffDashboardHelper
  def return_no_waiver_id(user)
    user.read_and_accepted_waiver_form ? id = "" : id = "no-waiver"
    id
  end

  # "3 days ago at Space Name": when the user's previous visit (the second newest
  # session) ended and its space. Blank for a first visit. Preload :lab_sessions where
  # many users are listed.
  def previous_visit_text(user)
    visit = user.previous_lab_session
    visit_text(visit)
  end

  # "3 days ago at Space Name" for the user's newest session.
  def last_seen_text(user)
    visit = user.latest_lab_session
    visit_text(visit)
  end

  private

  def visit_text(visit)
    "#{time_ago_in_words(visit.sign_out_time)} ago at #{space_names[visit.space_id]}" if visit
  end

  # Space names by id: the rows name spaces other than the one on screen.
  def space_names
    @space_names ||= Space.pluck(:id, :name).to_h
  end
end

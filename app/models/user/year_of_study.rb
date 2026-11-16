# frozen_string_literal: true

# The year of study is kept as a reference point: the year as it was entered
# (year_of_study_entered) and the day it was set (year_of_study_set_on). The
# current year is counted from there: a student moves up one year on the first
# day of the month their account was created in, every year after the year it
# was created, up to year 8; the next move after year 8 makes them Alumni. Any
# other entered value (blank, 9 and up, text) becomes Alumni at the first move,
# and an empty or Alumni year stays as it is. Only students move up: for other
# identities the entered year is the current one.
#
# The legacy users.year_of_study column keeps the year as last written by a
# form and is not moved up any more. Reports outside the app read the current
# year from the reporting_user_years database view, which counts it the same
# way (see the migration that creates it).
module User::YearOfStudy
  extend ActiveSupport::Concern

  LAST_NUMBERED_YEAR = 8
  ALUMNI = "Alumni"

  # How the reference point was set: by a person through the app, or by the
  # one-time backfill (from the last run of the old monthly task, for accounts
  # it still moved up, or from the last run before the account was marked
  # inactive, for accounts it had stopped moving up).
  SET_BY = %w[entered backfill_last_run backfill_marked_inactive].freeze

  # Writing the year of study records it as the new reference point.
  def year_of_study=(value)
    super
    record_year_of_study(year_of_study)
  end

  # A change of identity starts or stops the yearly moves, so the year reached
  # under the old identity becomes the new reference point.
  def identity=(value)
    year = current_year_of_study
    super
    record_year_of_study(year) if identity_changed?
  end

  class_methods do
    # The current year of study of each user of the relation, read with only the
    # columns the count needs.
    def current_years_of_study(on: Time.zone.today)
      select(:id, :identity, :created_at, :year_of_study_entered, :year_of_study_set_on)
        .map { |user| user.current_year_of_study(on: on) }
    end
  end

  def current_year_of_study(on: Time.zone.today)
    moves = student? ? year_of_study_moves(on) : 0
    return year_of_study_entered if moves.zero?

    moved_year_of_study(moves)
  end

  private

  def record_year_of_study(year)
    self.year_of_study_entered = year
    self.year_of_study_set_on = Time.zone.today
    self.year_of_study_set_by = "entered"
  end

  # The number of first-of-the-creation-month days after the set day, up to and
  # including `on`, leaving out the year the account was created.
  def year_of_study_moves(on)
    return 0 if created_at.nil? || year_of_study_set_on.nil?

    created = created_at.in_time_zone
    month = created.month
    first = [year_of_study_set_on.year + (month > year_of_study_set_on.month ? 0 : 1), created.year + 1].max
    last = on.year - (month > on.month ? 1 : 0)
    [last - first + 1, 0].max
  end

  def moved_year_of_study(moves)
    entered = year_of_study_entered
    return entered if entered.nil? || entered == ALUMNI

    year = entered[/\A\d+/].to_i
    reached = year + moves
    year.between?(1, LAST_NUMBERED_YEAR - 1) && reached <= LAST_NUMBERED_YEAR ? reached.to_s : ALUMNI
  end
end

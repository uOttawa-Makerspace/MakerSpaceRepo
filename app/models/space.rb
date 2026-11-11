# frozen_string_literal: true

class Space < ApplicationRecord
  has_many :pi_readers
  has_many :keys, dependent: :nullify
  has_many :key_requests, dependent: :nullify
  has_many :walk_in_safety_sheets
  has_many :lab_sessions
  has_many :visitors, -> { distinct }, through: :lab_sessions, source: :user
  has_and_belongs_to_many :trainings
  has_many :training_sessions
  has_many :certifications, through: :training_sessions
  has_many :volunteer_tasks
  has_many :popular_hours, dependent: :destroy
  has_many :shadowing_hours
  has_many :users_with_current_space, -> { including_deleted }, class_name: "User"
  has_many :staff_spaces, dependent: :destroy
  has_many :shifts, dependent: :destroy
  has_many :sub_spaces, dependent: :destroy
  has_many :sub_space_bookings, through: :sub_spaces
  has_many :staff_needed_calendars, dependent: :destroy
  has_many :space_manager_joins, dependent: :destroy
  has_many :space_managers, through: :space_manager_joins, source: :user
  has_many :staff, through: :staff_spaces, source: :user

  # A space with user history cannot be deleted: walk-in safety sheets, lab sessions, training sessions (with
  # their certifications and exams), volunteer tasks (with their hours) and sub space bookings feed reports and
  # course records. Nor can a space that is still the current space of a user (users.space_id): that column is
  # left as it is. The delete is refused with an explanation instead. The check runs before anything is
  # destroyed (prepend), so the sub spaces are not taken along with their bookings.
  BLOCKING_ASSOCIATIONS = %i[
    walk_in_safety_sheets lab_sessions training_sessions volunteer_tasks sub_space_bookings users_with_current_space
  ].freeze
  REFUSAL_KEY = :"restrict_dependent_destroy.has_many"
  before_destroy :refuse_deletion_while_history_exists, prepend: true

  after_create :create_popular_hours, unless: -> { Rails.env.test? }

  validates :name,
            presence: true,
            uniqueness: true

  # The records this space still has, as the associations that block its deletion. Empty when it can be deleted.
  def blocking_records
    BLOCKING_ASSOCIATIONS.select { |association| public_send(association).exists? }
  end

  # Why this space cannot be deleted, one message per kind of history, built the way restrict_with_error builds its
  # message (the same key and association names, so model-scoped overrides and the locale apply).
  def deletion_refusals
    blocking_records.map { |association| errors.generate_message(:base, REFUSAL_KEY, record: refusal_record_name(association)) }
  end

  # Visits keep their user after the account is soft-deleted, so the rosters below leave deleted
  # users out explicitly: they are not listed as in, or recently in, a space. The join reads the
  # user's deleted flag in the same query (the association itself reaches deleted users).
  def signed_in_users
    visible_lab_sessions
      .where("sign_out_time > ?", Time.zone.now)
      .order(sign_out_time: :desc)
      .map(&:user)
      .uniq
  end

  # For tables that show each user's previous visit.
  def signed_in_users_with_history(with_sheets: false)
    with_visit_history(signed_in_users, with_sheets: with_sheets)
  end

  def recently_signed_out_users
    users =
      visible_lab_sessions
        .where("sign_out_time < ?", Time.zone.now)
        .where.not(user_id: lab_sessions.where("sign_out_time > ?", Time.zone.now).where.not(user_id: nil).select(:user_id))
        .order(sign_out_time: :asc)
        .last(20)
        .map(&:user)
        .uniq

    users
        .sort_by do |user|
          user.lab_sessions.where(space: self).last.sign_out_time
        end
        .reverse
  end

  # For tables that show each user's previous visit.
  def recently_signed_out_users_with_history
    with_visit_history(recently_signed_out_users)
  end

  def visible_lab_sessions
    lab_sessions.includes(:user).where(users: { deleted: false })
  end
  private :visible_lab_sessions

  # A user query for this space's dashboard rows: spaces that ask for a walk-in safety sheet show
  # whether each user has signed one, so those rows load the sheets with the users.
  def including_walk_in_sheets(users)
    needs_walk_in_safety_sheet? ? users.includes(:walk_in_safety_sheets) : users
  end

  # Loads what the dashboard rows read: each user's visits and, with with_sheets in a space that
  # asks for a walk-in sheet, their sheets (only signed-in rows show those).
  def with_visit_history(users, with_sheets: false)
    associations = [:lab_sessions]
    associations << :walk_in_safety_sheets if with_sheets && needs_walk_in_safety_sheet?
    ActiveRecord::Associations::Preloader.new(records: users, associations: associations).call
    users
  end
  private :with_visit_history

    def create_popular_hours
      # Optimization: Prepare data in memory
      records = []
      (0..6).each do |weekday|
        (0..23).each do |hour|
          records << { space_id: id, hour: hour, day: weekday, created_at: Time.current, updated_at: Time.current }
        end
      end
      
      # Single SQL Insert
      PopularHour.insert_all(records)
    end

  def makerspace?
    name.eql?("Makerspace")
  end

  def ceed?
    name.eql?("CEED")
  end

  def jmts?
    name.eql?("JMTS")
  end

  # FIXME: This should be a checkbox somewhere
  def needs_walk_in_safety_sheet?
    name.eql?("Brunsfield Centre") || name.eql?("MTC")
  end

  def assigned_color
    colors = [
      [230, 25, 75], # #e6194b
      [60, 180, 75], # #3cb44b
      [255, 225, 25], # #ffe119
      [67, 99, 216], # #4363d8
      [245, 130, 49], # #f58231
      [145, 30, 180], # #911eb4
      [70, 240, 240], # #46f0f0
      [240, 50, 230], # #f032e6
      [128, 128, 0], # #808000
      [0, 128, 128] # #008080
    ]
    colors[id % colors.size]
  end

  def assigned_color_hex
    format("#%02x%02x%02x", *assigned_color)
  end

  # Black or white, whichever reads better on the assigned colour. White wins only when the colour's relative
  # luminance is below the point where black and white give the same contrast ratio (about 0.179).
  def assigned_color_text
    linear = assigned_color.map { |c| c / 255.0 }.map { |c| c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055)**2.4 }
    luminance = (0.2126 * linear[0]) + (0.7152 * linear[1]) + (0.0722 * linear[2])
    luminance < 0.179 ? "#ffffff" : "#000000"
  end

  private

  def refusal_record_name(association)
    self.class.human_attribute_name(association).downcase
  end

  def refuse_deletion_while_history_exists
    history = blocking_records
    return if history.empty?

    history.each { |association| errors.add(:base, REFUSAL_KEY, record: refusal_record_name(association)) }
    throw :abort
  end
end

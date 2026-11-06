class Event < ApplicationRecord
  belongs_to :created_by, class_name: 'User'
  belongs_to :space
  has_many :event_assignments, dependent: :destroy
  has_many :users, through: :event_assignments, source: :user

  belongs_to :training, optional: true
  belongs_to :course_name, optional: true

  validates :start_time, :end_time, :created_by_id, :space_id, :event_type, presence: true
  
  # Only require a training if event_type is 'training' AND it's not a draft
  validates :training_id, presence: true, if: -> { event_type == 'training' && !draft? }

  validate :start_time_must_be_before_end_time
  validates :recurrence_rule, recurrence_rule: true
  validate :weekly_frequency_must_contain_days

  # Single source of truth for event title formatting across the entire app
  def display_title(include_draft_indicator: true)
    prefix = (draft && include_draft_indicator) ? '✎ ' : ''

    return "#{prefix}#{title}" unless title == event_type.capitalize && event_assignments.any?

    if event_type == 'training'
      t_name = training&.name || 'Training'
      details = [course_name&.name, language].compact_blank.join(' - ')
      details_str = details.present? ? " (#{details})" : ''
      assigned = event_assignments.map { |ea| ea.user&.name }.compact.join(', ')

      "#{prefix}#{t_name}#{details_str} for #{assigned}"
    else
      assigned = event_assignments.map { |ea| ea.user&.name }.compact.join(', ')
      "#{prefix}#{event_type.capitalize} for #{assigned}"
    end
  end

  # Queues the push of this event to Google Calendar, to be called once the change is committed. Drafts are never
  # pushed. The Google event id is chosen here, before the first push, so that a retried push cannot create a
  # second copy.
  #
  # When the event was moved to another space, pass the space it came from: its copy in the old calendar is then
  # removed too.
  def push_to_google_later(previous_space: nil)
    remove_from_previous_calendar(previous_space)
    return if draft

    assign_google_event_id
    GoogleCalendar::EventPushJob.perform_later(id)
  end

  # Queues the removal of a destroyed event's copy in Google Calendar. Takes what was read from the event before
  # it was destroyed.
  # Pass +event_id+ when the event still exists, so the removal is skipped if it has come back to that calendar.
  def self.remove_from_google_later(google_event_id, space, event_id: nil)
    return if google_event_id.blank?

    calendar_id = GoogleCalendar::EventPublisher.calendar_id_for(space)
    GoogleCalendar::EventDeleteJob.perform_later(*[google_event_id, calendar_id, event_id].compact)
  end

  private

  def remove_from_previous_calendar(previous_space)
    return if previous_space.nil?
    return if GoogleCalendar::EventPublisher.calendar_id_for(previous_space) ==
              GoogleCalendar::EventPublisher.calendar_id_for(space)

    Event.remove_from_google_later(google_event_id, previous_space, event_id: id)
  end

  def assign_google_event_id
    return if google_event_id.present?

    Event.where(id: id, google_event_id: [nil, ""]).update_all(google_event_id: SecureRandom.hex(16))
    self.google_event_id = Event.where(id: id).pick(:google_event_id)
    clear_attribute_changes([:google_event_id])
  end

  def start_time_must_be_before_end_time
    return unless start_time.present? && end_time.present? && start_time >= end_time
    errors.add(:start_time, "must be before the end time")
  end
  
  def weekly_frequency_must_contain_days
    if recurrence_rule.present? && recurrence_rule.include?("FREQ=WEEKLY") && !recurrence_rule.include?("BYDAY")
      errors.add(:recurrence_rule, "must include days of the week when using weekly frequency")
    end
  end
end

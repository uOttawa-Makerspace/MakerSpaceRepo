class Event < ApplicationRecord
  include Reschedulable
  # The longest span a calendar feed answers in one request (the staff calendar and the shifts API).
  MAX_FEED_RANGE = 100.days
  # The feed colour of an assignee with no colour in the space, and of an event nobody is assigned to.
  UNASSIGNED_COLOR = "#bbb"

  # Whether a feed range is longer than the limit. An hour of slack lets a range counted in local days across a
  # clock change (an hour longer in seconds) through.
  def self.feed_range_too_long?(from, to)
    to - from > MAX_FEED_RANGE + 1.hour
  end

  # The event types stored for a space, alphabetical.
  def self.types_in(space_id) = where(space_id: space_id).distinct.order(:event_type).pluck(:event_type)

  belongs_to :created_by, class_name: 'User'
  # Who last edited the event in the admin calendar; empty for an event nobody has edited since it was created.
  belongs_to :updated_by, class_name: 'User', optional: true
  belongs_to :space
  has_many :event_assignments, dependent: :destroy
  has_many :users, through: :event_assignments, source: :user

  belongs_to :training, optional: true
  belongs_to :course_name, optional: true

  validates :start_time, :end_time, :created_by_id, :space_id, :event_type, presence: true
  
  # Only require a training if event_type is 'training' AND it's not a draft
  validates :training_id, presence: true, if: -> { event_type == 'training' && !draft? }

  validate :start_time_must_be_before_end_time
  validates :recurrence_rule, recurrence_rule: true, if: :check_recurrence_rule?
  validate :weekly_frequency_must_contain_days

  # The repeat rule is checked when it changes and when a draft is published (not when an event goes back to draft), so a
  # stored rule that is no longer valid cannot go live but does not block other edits.
  def check_recurrence_rule?
    will_save_change_to_recurrence_rule? || will_save_change_to_draft?(from: true, to: false)
  end

  # Publishes the space's drafts that start in the range, as `by`, and yields each one once it is saved (the caller
  # pushes it to Google). Returns the published events and the ones that could not be saved, with their errors.
  def self.publish_drafts(space_id, range, by:)
    published = []
    failed = []
    where(space_id: space_id, start_time: range, draft: true).find_each do |event|
      next failed << event unless event.publish(by: by)

      published << event
      yield event
    end
    [published, failed]
  end

  # Loads, in one query for the list, the training of each event whose display_title names it.
  def self.preload_title_trainings(events)
    titled = events.select { |event| event.event_type == 'training' && event.titled_by_assignees? }
    ActiveRecord::Associations::Preloader.new(records: titled, associations: :training).call
  end

  # Whether display_title names the assignees (and, for a training, the training) instead of the stored title: the
  # title is the type's own name and someone is assigned.
  def titled_by_assignees?
    title == event_type.capitalize && event_assignments.any?
  end

  # Single source of truth for event title formatting across the entire app
  def display_title(include_draft_indicator: true)
    prefix = (draft && include_draft_indicator) ? '✎ ' : ''

    return "#{prefix}#{title}" unless titled_by_assignees?

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

  # The event as the admin calendar draws it; staff_colors holds each staff member's colour in the space, by user id.
  def feed_row(staff_colors)
    { id: "event-#{id}", title: display_title(include_draft_indicator: true),
      start: start_time.iso8601, end: end_time.iso8601, **feed_recurrence,
      allDay: CalendarTime.all_day?(start_time, end_time),
      extendedProps: { name: event_type.capitalize, draft: draft, description: description, eventType: event_type,
                       trainingId: training_id, language: language, course_name: course_name,
                       assignedUsers: feed_assignees, background: feed_background(staff_colors) } }
  end

  # Asks for the push of this event to Google Calendar and queues it, to be called once the change is committed.
  # The ask is recorded first (GoogleCalendar::PendingChange), so a push that could not be queued is queued again
  # later. Drafts are never
  # pushed. The Google event id is chosen here, before the first push, so that a retried push cannot create a
  # second copy. The job moves the Google copy first if the event now belongs to another calendar.
  def push_to_google_later
    return if draft

    assign_google_event_id
    GoogleCalendar::PendingChange.ask_push(id).enqueue
  end

  # The Google calendar that holds this event's Google copy: the recorded one, else the calendar of its space.
  def google_calendar
    google_calendar_id.presence || GoogleCalendar::EventPublisher.calendar_id_for(space)
  end

  # Makes the event a draft. The Google ids are cleared because Google does not let a removed event's id be
  # created again; a later publish chooses a new one. Returns false when the event cannot be saved. The caller
  # reads google_event_id and google_calendar first and, once this has committed, queues the removal of the
  # Google copy with Event.remove_from_google_later.
  def unpublish(by:)
    update(draft: true, updated_by: by, google_event_id: nil, google_calendar_id: nil)
  end

  # Makes the event live, as `by`. Returns false when the event cannot be saved. The caller pushes it to Google once
  # this has committed (push_to_google_later).
  def publish(by:)
    update(draft: false, updated_by: by)
  end

  # Queues the removal of a destroyed event's copy in Google Calendar. Takes what was read from the event
  # (id, google_event_id and google_calendar) before it was destroyed.
  def self.remove_from_google_later(google_event_id, calendar_id, event_id)
    return if google_event_id.blank?

    GoogleCalendar::PendingChange.ask_removal(event_id, google_event_id, calendar_id).enqueue
  end

  private

  # A series' rule and its length in milliseconds (the browser repeats it); nothing for a one-off.
  def feed_recurrence
    return {} if recurrence_rule.blank?

    { rrule: RecurrenceRule.new(recurrence_rule, start_time).in_toronto_time,
      duration: (end_time.to_time - start_time.to_time) * 1000 }
  end

  def feed_assignees
    return [{ id: 0, name: "Unassigned" }] if event_assignments.empty?

    event_assignments.map { |assignment| { id: assignment.user&.id, name: assignment.user&.name } }
  end

  # Equal stripes in each assignee's colour; a draft is faded.
  def feed_background(staff_colors)
    colors = event_assignments.map { |assignment| staff_colors[assignment.user_id] || UNASSIGNED_COLOR }
    colors = [UNASSIGNED_COLOR] if colors.empty?
    width = 100.0 / colors.size
    stops = colors.map.with_index { |color, i| "#{color} #{width * i}%, #{color} #{width * (i + 1)}%" }
    "linear-gradient(to right, #{stops.join(', ')});#{' opacity: 0.8;' if draft}"
  end

  def assign_google_event_id
    return if google_event_id.present?

    Event.where(id: id, google_event_id: [nil, ""]).update_all(google_event_id: SecureRandom.hex(16))
    self.google_event_id = Event.where(id: id).pick(:google_event_id)
    clear_attribute_changes([:google_event_id])
  end

  def start_time_must_be_before_end_time
    return unless start_time.present? && end_time.present? && start_time >= end_time
    errors.add(:start_time, :before_end_time)
  end
  
  def weekly_frequency_must_contain_days
    if recurrence_rule.present? && recurrence_rule.include?("FREQ=WEEKLY") && !recurrence_rule.include?("BYDAY")
      errors.add(:recurrence_rule, :weekly_needs_days)
    end
  end
end

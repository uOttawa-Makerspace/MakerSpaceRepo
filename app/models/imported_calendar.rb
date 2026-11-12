# frozen_string_literal: true

# An external calendar (an ICS feed) read onto the same engine as the stored events: each event is one-off or a
# RecurringSeries, with the display attributes of the feed (uid, summary, description).
#
#   calendar = ImportedCalendar.load(url, name: "Hours", color: "#123456")
#   calendar.entries  # Entry list; entry.series is nil for a one-off
#
# Per UID: the master's repeat rule goes to the series as the file wrote it, its start is read in its own zone
# (a TZID icalendar resolves from an IANA name, the file's VTIMEZONE or a Windows name; no zone is Toronto), the
# dates and instants it leaves out are exclusions, and each modified instance (RECURRENCE-ID) is a one-off of its
# own at its own times, unless it is STATUS:CANCELLED, which is just an exclusion. A cancelled master is left out,
# as is anything that ended more than two months ago.
#
# Not supported, because no feed in use needs them and nothing reads them: RDATE, and RANGE=THISANDFUTURE on a
# RECURRENCE-ID (the instance is treated as one instance). An event with either is read without it.
#
# The feed's body is cached for ten minutes, encrypted (a private link's calendar is private), under a key made
# from a digest of the link. A series whose rule the engine refuses, and an event with no usable start, are
# reported and left out so the rest of the feed still loads.
class ImportedCalendar
  ZONE = RecurrenceRule::ZONE
  KEEP_FOR = 2.months
  CACHE_FOR = 10.minutes
  # What a reader of the cached entry that is already being rebuilt keeps serving for.
  REBUILD_GRACE = 10.seconds
  CIPHER = "aes-256-gcm"

  # `recurrence_id` is the original instant of a modified instance (nil otherwise); `series` is nil for a one-off.
  # `ends_at` is nil when the event has no end.
  Entry = Data.define(:uid, :recurrence_id, :summary, :description, :all_day, :starts_at, :ends_at, :series) do
    # The row key in the calendar: a modified instance is told apart from its series by its original instant.
    def key = recurrence_id ? "#{uid}_#{recurrence_id.to_i}" : uid
  end

  attr_reader :id, :color, :name, :entries

  # `fresh: true` reads the feed again even when a copy is cached (the refresh button).
  def self.load(url, name:, color:, fresh: false)
    new(url, name, color).tap { |calendar| calendar.read(fresh) }
  end

  # The time of an icalendar date or date-time, in its own zone: a date is midnight in `date_zone`, a time with no
  # zone (or one icalendar cannot resolve) is Toronto wall time. Nil for no value.
  def self.time_of(value, date_zone = ZONE)
    return if value.nil?
    return date_zone.local(value.year, value.month, value.day) if value.is_a?(Icalendar::Values::Date) || value.instance_of?(::Date)

    raw = value.value
    return ZONE.local(raw.year, raw.month, raw.day, raw.hour, raw.min, raw.sec) if raw.instance_of?(::DateTime) && raw.offset.zero?

    value.to_time.in_time_zone(zone_named(Array(value.ical_params["tzid"]).first))
  end

  # The IANA or Windows zone name as a zone; Toronto for any other (a custom name with its own VTIMEZONE).
  def self.zone_named(tzid)
    ActiveSupport::TimeZone[tzid.to_s] || ActiveSupport::TimeZone[Icalendar::Offset::WindowsToIana::WINDOWS_TO_IANA[tzid].to_s] || ZONE
  end

  # The feed body, or nil when the server gave none. A copy is kept for ten minutes, encrypted, never under the
  # link itself (it holds the secret of a private calendar); only a body is kept, not a failure.
  def self.body(url, fresh: false)
    key = ["ics-body", Digest::SHA256.hexdigest(url)]
    sealed = Rails.cache.fetch(key, expires_in: CACHE_FOR, race_condition_ttl: REBUILD_GRACE, force: fresh, skip_nil: true) do
      body = IcsFetcher.get(url, timeout: 10)
      body && cipher.encrypt_and_sign(body)
    end
    sealed && cipher.decrypt_and_verify(sealed)
  end

  # The key comes from the application secret, so it needs no setting of its own and changes with it (a copy made
  # under the old secret is then unreadable, and gone within ten minutes).
  def self.cipher
    ActiveSupport::MessageEncryptor.new(
      Rails.application.key_generator.generate_key("imported calendar body", ActiveSupport::MessageEncryptor.key_len(CIPHER)),
      cipher: CIPHER
    )
  end

  def initialize(url, name, color)
    @url = url.to_s
    @id = Digest::MD5.hexdigest(@url)
    @name = name
    @color = color
    @entries = []
    @fetched = false
    @failed = false
  end

  # Whether the feed could not be read: no body, a fetch or parse error, or a body with no calendar in it.
  def failed? = @failed

  # Whether the server gave a body (or an error was raised reading it) rather than nothing at all.
  def fetched? = @fetched

  # Reads the feed. The error is logged by host only: a private link holds its secret in the path.
  def read(fresh)
    body = self.class.body(@url, fresh: fresh)
    @fetched = !body.nil?
    calendars = body ? Icalendar::Calendar.parse(body) : []
    @failed = calendars.empty?
    @entries = calendars.flat_map { |calendar| calendar.events.group_by(&:uid).flat_map { |_uid, group| group_entries(group) } }
  rescue StandardError => e
    Rails.logger.error("ICS parse error for #{IcsFetcher.host(@url)}: #{e.class}")
    @entries = []
    @fetched = @failed = true
  end

  private

  # The entries of one UID: the series (or single event) itself, then each modified instance of it that is not
  # cancelled.
  def group_entries(group)
    master = group.find { |event| event.recurrence_id.nil? }
    overrides = group.select { |event| event.recurrence_id.present? }
    [master && master_entry(master, overrides), *overrides.map { |event| override_entry(event) }].compact
  end

  def master_entry(event, overrides)
    return if cancelled?(event)

    entry = entry_for(event, nil)
    entry && (event.rrule.present? ? series_entry(entry, event, overrides) : kept(entry))
  end

  def override_entry(event)
    return if cancelled?(event)

    entry = entry_for(event, ImportedCalendar.time_of(event.recurrence_id))
    entry && kept(entry)
  end

  def cancelled?(event) = event.status.to_s.casecmp?("CANCELLED")

  # The entry for the event's own times, or nil (reported) when it has no usable start.
  def entry_for(event, recurrence_id)
    starts_at = ImportedCalendar.time_of(event.dtstart)
    return report("ICS event has no usable start", event) if starts_at.nil?

    all_day = event.dtstart.is_a?(Icalendar::Values::Date)
    Entry.new(uid: event.uid, recurrence_id: recurrence_id, summary: event.summary, description: event.description, all_day: all_day,
              starts_at: starts_at, ends_at: ImportedCalendar.time_of(event.dtend, starts_at.time_zone), series: nil)
  end

  # A single event or modified instance, unless it ended more than two months ago.
  def kept(entry)
    entry if (entry.ends_at || entry.starts_at) >= cutoff
  end

  # A repeating event, unless the series ended more than two months ago (by UNTIL or after its COUNT). A rule the
  # engine refuses is reported and the series left out.
  def series_entry(entry, event, overrides)
    ends_at = entry.ends_at || (entry.all_day ? entry.starts_at.advance(days: 1) : entry.starts_at)
    series = RecurringSeries.from_ics(event, overrides, starts_at: entry.starts_at, ends_at: ends_at)
    entry.with(series: series) unless ended?(series)
  rescue ArgumentError, RRule::InvalidRRule => e
    report(e, event)
  end

  def ended?(series)
    series.occurrences_starting_in(cutoff..(cutoff + RecurringSeries::MAX_YEARS.years), limit: 1).occurrences.empty?
  end

  def cutoff = Time.current - KEEP_FOR

  # Reports an event that cannot be placed on the calendar; returns nil so the caller leaves it out.
  def report(problem, event)
    error = problem.is_a?(StandardError) ? problem : ArgumentError.new(problem)
    Rails.error.report(error, handled: true, severity: :warning,
                              context: { event_uid: event.uid.to_s, calendar: @id, error_class: error.class.name })
    nil
  end
end

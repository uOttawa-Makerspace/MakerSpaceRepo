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
# The feed's body, and the entries made from it, are cached for ten minutes, encrypted (a private link's calendar is
# private): the body under a digest of the link, the entries under a digest of the body and of the code that made them.
# A rule that does not pass the checks stored rules pass (value ranges, never repeating) is reported and the event is
# shown once at its own start; an event that cannot be read at all is reported and left out; an event with no usable
# start is reported and left out; so one bad event never empties the feed. A feed keeps its first MAX_EVENTS events.
class ImportedCalendar
  ZONE = RecurrenceRule::ZONE
  KEEP_FOR = 2.months
  CACHE_FOR = 10.minutes
  # What a reader of the cached entry that is already being rebuilt keeps serving for.
  REBUILD_GRACE = 10.seconds
  CIPHER = "aes-256-gcm"
  MAX_EVENTS = 5000
  MAX_UID = 120
  MAX_UIDS_REPORTED = 5
  # Changes whenever the code that makes entries changes, so a cached entry is never read by other code.
  VERSION = Digest::SHA256.hexdigest(%w[models/imported_calendar models/recurring_series validators/recurrence_rule_validator]
                                       .map { |name| Rails.root.join("app/#{name}.rb").read }.join)

  # `recurrence_id` is the original instant of a modified instance (nil otherwise); `series` is nil for a one-off.
  # `ends_at` is nil when the event has no end.
  # What is reported (its message holds no text from the feed).
  Problem = Class.new(StandardError)

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
  # zone is Toronto wall time, and a zone name that is neither IANA nor Windows (a custom name with its own
  # VTIMEZONE) keeps the instant and is Toronto, yielding the name to the block if there is one. Nil for no value.
  def self.time_of(value, date_zone = ZONE, &unknown)
    return if value.nil?
    return date_zone.local(value.year, value.month, value.day) if value.is_a?(Icalendar::Values::Date) || value.instance_of?(::Date)

    zone = zone_of(value, &unknown)
    raw = value.value
    return ZONE.local(raw.year, raw.month, raw.day, raw.hour, raw.min, raw.sec) if raw.instance_of?(::DateTime) && raw.offset.zero?

    value.to_time.in_time_zone(zone)
  end

  # The zone a time is in: the IANA or Windows zone its TZID names, else Toronto.
  def self.zone_of(value)
    tzid = Array(value.ical_params["tzid"]).first
    zone = ActiveSupport::TimeZone[tzid.to_s] || ActiveSupport::TimeZone[Icalendar::Offset::WindowsToIana::WINDOWS_TO_IANA[tzid].to_s]
    yield tzid if tzid && zone.nil? && block_given?
    zone || ZONE
  end

  # The feed body, or nil when the server gave none (or an empty one).
  def self.body(url, fresh: false)
    cached(["ics-body", Digest::SHA256.hexdigest(url)], fresh: fresh) { IcsFetcher.get(url, timeout: 10).presence }
  end

  # The block's value, kept for ten minutes, encrypted (Marshal, which is safe here: only the application can have
  # written a value that decrypts), never under the link itself (it holds the secret of a private calendar). A nil is
  # not kept, so neither is a failure. A copy that cannot be read is reported and made again.
  def self.cached(key, fresh: false, &block)
    sealed = Rails.cache.fetch(key, expires_in: CACHE_FOR, race_condition_ttl: REBUILD_GRACE, force: fresh, skip_nil: true) do
      value = block.call
      value && cipher(key.first).encrypt_and_sign(value)
    end
    return unless sealed

    unseal(sealed, key.first) || (cached(key, fresh: true, &block) unless fresh)
  end

  # The value of a cached copy, or nil (reported, with the class of the error and no link) when it cannot be read: it
  # was sealed under another secret, or by other code (Marshal cannot load it).
  def self.unseal(sealed, kind)
    cipher(kind).decrypt_and_verify(sealed)
  rescue ActiveSupport::MessageEncryptor::InvalidMessage, ArgumentError, TypeError => e
    Rails.logger.error("ICS cache copy unreadable: #{e.class}")
    Rails.error.report(Problem.new("imported calendar cache copy unreadable: #{e.class}"), handled: true, severity: :warning,
                                                                                           context: { cache: kind })
    nil
  end

  # One key per kind of cached value, from the application secret, so it needs no setting of its own and changes with it
  # (a copy made under the old secret is reported, made again, and gone within ten minutes).
  def self.cipher(kind)
    ActiveSupport::MessageEncryptor.new(
      Rails.application.key_generator.generate_key("imported calendar #{kind}", ActiveSupport::MessageEncryptor.key_len(CIPHER)),
      cipher: CIPHER, serializer: Marshal
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
    @unknown_zones = Set.new
    @problems = Hash.new(0)
    @problem_uids = []
  end

  # Whether the feed could not be read: no body, a fetch or parse error, or a body with no calendar in it.
  def failed? = @failed

  # Whether the server gave a body (or an error was raised reading it) rather than nothing at all.
  def fetched? = @fetched

  # Reads the feed. The error is logged by host only: a private link holds its secret in the path.
  def read(fresh)
    body = self.class.body(@url, fresh: fresh)
    @fetched = !body.nil?
    @failed, @entries = body ? entries_of(body, fresh) : [true, []]
  rescue StandardError => e
    report_failure(e)
    @entries = []
    @fetched = @failed = true
  end

  private

  # Whether the feed is unreadable, and its entries: made once per body (and per version of this code), then kept.
  def entries_of(body, fresh)
    key = ["ics-entries", VERSION, Digest::SHA256.hexdigest(body)]
    self.class.cached(key, fresh: fresh) { read_calendars(body) }
  end

  # A feed that cannot be parsed is reported once, with the entries (so it is kept like any other result).
  def read_calendars(body)
    calendars = Icalendar::Calendar.parse(body)
    events = calendars.flat_map(&:events)
    report_later("too many events") if events.size > MAX_EVENTS
    entries = events.first(MAX_EVENTS).group_by(&:uid).flat_map { |_uid, group| group_entries(group) }
    @unknown_zones.each { report_later("unknown time zone") }
    report_problems
    [calendars.empty?, entries]
  rescue StandardError => e
    report_failure(e)
    report_problems(Problem.new("imported calendar could not be read: #{e.class}"))
    [true, []]
  end

  def report_failure(error)
    Rails.logger.error("ICS parse error for #{IcsFetcher.host(@url)}: #{error.class}")
  end

  # The entries of one UID: the series (or single event) itself, then each modified instance of it that is not
  # cancelled.
  def group_entries(group)
    master = group.find { |event| event.recurrence_id.nil? }
    overrides = group.select { |event| event.recurrence_id.present? }
    [master && guarded(master) { master_entry(master, overrides) },
     *overrides.map { |event| guarded(event) { override_entry(event) } }].compact
  end

  # One event that cannot be read is reported and left out; it never stops the rest of the feed.
  def guarded(event)
    yield
  rescue StandardError => e
    report_later(e.class.name, event.uid)
  end

  def master_entry(event, overrides)
    return if cancelled?(event)

    entry = entry_for(event, nil)
    entry && (event.rrule.present? ? repeating_entry(entry, event, overrides) : kept(entry))
  end

  def override_entry(event)
    return if cancelled?(event)

    entry = entry_for(event, ImportedCalendar.time_of(event.recurrence_id))
    entry && kept(entry)
  end

  def cancelled?(event) = event.status.to_s.casecmp?("CANCELLED")

  # The entry for the event's own times, or nil (reported) when it has no usable start.
  def entry_for(event, recurrence_id)
    starts_at = zoned_time(event.dtstart)
    return report_later("ICS event has no usable start", event.uid) if starts_at.nil?

    Entry.new(uid: event.uid.to_s, recurrence_id: recurrence_id, summary: event.summary&.to_s, description: event.description&.to_s,
              all_day: event.dtstart.is_a?(Icalendar::Values::Date), starts_at: starts_at,
              ends_at: zoned_time(event.dtend, starts_at.time_zone), series: nil)
  end

  # A time of the event; a zone name that cannot be resolved is noted, to be reported once for the feed.
  def zoned_time(value, date_zone = ZONE)
    ImportedCalendar.time_of(value, date_zone) { |tzid| @unknown_zones << tzid.to_s }
  end

  # A single event or modified instance, unless it ended more than two months ago.
  def kept(entry)
    entry if (entry.ends_at || entry.starts_at) >= cutoff
  end

  # A repeating event. A rule that fails the checks stored rules pass is reported and the event is shown once, at its
  # own start.
  def repeating_entry(entry, event, overrides)
    problem = RecurrenceRuleValidator.error_for("RRULE:#{event.rrule.first.value_ical}", entry.starts_at, RecurrenceRuleValidator::IMPORTED)
    return series_entry(entry, event, overrides) unless problem

    report_later(problem, event.uid)
    kept(entry)
  end

  # The series, unless it ended more than two months ago (by UNTIL or after its COUNT).
  def series_entry(entry, event, overrides)
    ends_at = entry.ends_at || (entry.all_day ? entry.starts_at.advance(days: 1) : entry.starts_at)
    series = RecurringSeries.from_ics(event, overrides, starts_at: entry.starts_at, ends_at: ends_at)
    entry.with(series: series) unless ended?(series)
  end

  def ended?(series)
    series.occurrences_starting_in(cutoff..(cutoff + RecurringSeries::MAX_YEARS.years), limit: 1).occurrences.empty?
  end

  def cutoff = Time.current - KEEP_FOR

  # Notes something that cannot be placed on the calendar, by kind (a fixed text, or an error class) and the event's uid;
  # returns nil so the caller leaves the event out. report_problems sends them as one report.
  def report_later(kind, uid = nil)
    @problems[kind] += 1
    @problem_uids << uid.to_s.truncate(MAX_UID) if uid && @problem_uids.size < MAX_UIDS_REPORTED
    nil
  end

  # One report per feed build: how many problems of each kind, and the first few event uids. Never the link, the rule
  # or any text of the feed.
  def report_problems(error = nil)
    return if @problems.empty? && error.nil?

    error ||= Problem.new("#{@problems.values.sum} events of an imported calendar could not be read as written")
    Rails.error.report(error, handled: true, severity: :warning,
                              context: { calendar: @id, kinds: @problems.to_h, event_uids: @problem_uids })
  end
end

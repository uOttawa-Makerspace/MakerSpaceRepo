class PopularHour < ApplicationRecord
  belongs_to :space, optional: true

  def self.from_space(space_id)
    space = Space.find_by(id: space_id)
    return if space.blank?
    PopularHour.where(space: space).order(day: :asc, hour: :asc)
  end

  LIVE_SINCE_KEY = "popular_hours_live_since"
  LIVE_THROUGH_KEY = "popular_hours_live_through"

  # Folds the head count of the hour in progress into the running mean of its (weekday, hour) row, for every
  # space that has people in it. Weekday and hour are read in Time.zone, the same zone the lab session window
  # is cut in, so the row does not depend on the host's clock. Run hourly (config/recurring.yml). The hours it
  # has recorded are noted in Setting, so a backfill leaves them alone.
  def self.record_current_hour!(now = Time.zone.now)
    with_fold_lock do
      record_hour!(now)
      note_live_run(now)
    end
  end

  # The folds are read-modify-write on shared rows, so the hourly task and the backfill (and two backfills) take
  # this transaction-level advisory lock before folding: they run one after the other and no update is lost or
  # counted twice. The lock is released when the transaction ends.
  FOLD_LOCK_KEY = Zlib.crc32("popular_hours_fold")

  def self.with_fold_lock(&)
    transaction do
      connection.select_value("SELECT 1 FROM pg_advisory_xact_lock($1)", "PopularHour fold lock", [FOLD_LOCK_KEY])
      yield
    end
  end

  # One sample taken at +at+: the running means of the rows for +at+'s weekday and hour. +historical+ takes the
  # sample of a past moment (see head_count). Returns the number of rows changed.
  def self.record_hour!(at, historical: false)
    changed = 0
    Space.find_each do |space|
      current_users = head_count(space, at, historical: historical)
      next if current_users.zero? # closed now: a zero would drag the mean toward nothing

      popular_hour = find_by(space_id: space.id, hour: at.hour, day: at.wday)
      next if popular_hour.blank?

      fold!(popular_hour, current_users)
      changed += 1
    end
    changed
  end

  # The distinct lab sessions of +space+ counted at +at+: those started during the hour, plus those whose
  # sign_out_time is after +at+. Live, nothing exists after the sample, so the hour runs to its end. For a past
  # moment (+historical+) the hour ends at +at+ and a session counts only once it had started, so sessions from
  # after the sample are left out.
  def self.head_count(space, at, historical: false)
    started = space.lab_sessions.between_dates_picked(at.beginning_of_hour, historical ? at : at.end_of_hour)
    present = space.lab_sessions.where("sign_out_time > ?", at)
    present = present.where("COALESCE(sign_in_time, created_at) <= ?", at) if historical
    (started.pluck(:id) | present.pluck(:id)).size
  end

  def self.fold!(popular_hour, current_users)
    new_count = popular_hour.count.next
    popular_hour.update(
      count: new_count,
      mean: ((popular_hour.count * popular_hour.mean) + current_users) / new_count,
      previous_mean: popular_hour.mean
    )
  end

  def self.note_live_run(now)
    hour = now.beginning_of_hour.iso8601
    Setting.set(LIVE_SINCE_KEY, hour) if Setting.get(LIVE_SINCE_KEY).blank?
    Setting.set(LIVE_THROUGH_KEY, hour)
  end
  private_class_method :note_live_run

  def self.popular_hours_per_period(start_date, end_date)
    lab_sessions_in_space =
      LabSession.between_dates_picked(
        start_date.beginning_of_day,
        end_date.end_of_day
      )
    data = {}
    Space.all.each do |space|
      data[space.id] = {}
      (0..6).each do |weekday|
        s =
          lab_sessions_in_space.where(
            "extract(dow from created_at) = ?",
            weekday
          ).where(space: space)
        data[space.id][weekday] = {}
        (0..23).each do |hour|
          if (start_date..end_date).count { |date| weekday == date.wday } == 0
            data[space.id][weekday][hour] = 0
          else
            data[space.id][weekday][hour] = (
              s.where("extract('hour' from created_at) = ?", hour).count.to_f /
                (start_date..end_date).count { |date| weekday == date.wday }
            ).round(2)
          end
        end
      end
    end
    data
  end
end

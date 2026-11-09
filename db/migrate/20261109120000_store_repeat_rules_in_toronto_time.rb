# frozen_string_literal: true

require "ice_cube"

# Rewrites the start line of stored repeat rules (events and staff
# unavailabilities) from a UTC stamp (DTSTART:20270310T150000Z) to Toronto
# wall-clock time (DTSTART;TZID=America/Toronto:20270310T100000), the form the
# calendar now writes. Only the DTSTART line changes, and only when the Toronto
# form starts at the same instant and expands to the same occurrences (over the
# life of the series, at most ten years or 1000 occurrences). Any other rule is
# left as it is and listed in the output. updated_at is not touched.
#
# Every rewrite is recorded in recurrence_rule_rewrites (table, row id, old and
# new text). down puts the recorded old text back and drops the record table; it
# refuses, changing nothing, while any rewritten rule has been edited since.
class StoreRepeatRulesInTorontoTime < ActiveRecord::Migration[8.1]
  TABLES = %w[events staff_unavailabilities].freeze
  ZONE = "America/Toronto"
  UTC_START = /^DTSTART:(\d{8}T\d{6})Z$/
  HORIZON = 10.years
  LIMIT = 1000
  RECORD_VERSION = "20261109120000"

  def up
    create_table :recurrence_rule_rewrites do |t|
      t.string :table_name, null: false
      t.bigint :record_id, null: false
      t.text :old_rule, null: false
      t.text :new_rule, null: false
      t.text :migration_version, null: false
      t.datetime :created_at, null: false
    end
    add_index :recurrence_rule_rewrites, %i[table_name record_id migration_version], unique: true,
                                                                                       name: "index_recurrence_rule_rewrites_once"

    TABLES.each { |table| rewrite(table) }
  end

  def down
    edited = edited_count
    if edited.positive?
      raise ActiveRecord::IrreversibleMigration,
            "#{edited} rewritten repeat rule(s) were changed after the rewrite; nothing was restored. " \
            "List them by comparing recurrence_rule_rewrites.new_rule with the current rules."
    end

    TABLES.each { |table| restore(table) }
    drop_table :recurrence_rule_rewrites
  end

  private

  def rewrite(table)
    rewritten = 0
    rows = select_rows("SELECT id, recurrence_rule FROM #{table} WHERE recurrence_rule LIKE '%DTSTART%' ORDER BY id")
    rows.each do |id, text|
      new_text, reason = toronto_form(text)
      next say("#{table} #{id} left as it is: #{reason}") if reason

      rewritten += record_rewrite(table, id, text, new_text)
    end
    say "#{table}: #{rewritten} of #{rows.size} rules with a start rewritten"
  end

  # The rule with its start in Toronto time, or nil and the reason it is kept.
  def toronto_form(text)
    stamps = text.scan(UTC_START).flatten
    return [nil, "not a single UTC start line"] unless stamps.size == 1 && text.scan(/^DTSTART/).size == 1

    old_start = Time.find_zone!("UTC").strptime(stamps.first, "%Y%m%dT%H%M%S").in_time_zone(ZONE)
    wall = old_start.strftime("%Y%m%dT%H%M%S")
    new_start = Time.find_zone!(ZONE).strptime(wall, "%Y%m%dT%H%M%S")
    return [nil, "the Toronto start gives other occurrences"] unless same_occurrences?(text, old_start, new_start)

    [text.sub(UTC_START, "DTSTART;TZID=#{ZONE}:#{wall}"), nil]
  rescue StandardError => e
    [nil, "the rule cannot be read (#{e.class})"]
  end

  def same_occurrences?(text, old_start, new_start)
    body = text.lines.map(&:strip).find { |line| line.start_with?("RRULE:") }&.delete_prefix("RRULE:")
    return false if body.blank?

    old_start == new_start && occurrences(body, old_start) == occurrences(body, new_start)
  end

  def occurrences(body, start)
    schedule = IceCube::Schedule.new(start)
    schedule.add_recurrence_rule(IceCube::Rule.from_ical(body))
    schedule.next_occurrences(LIMIT, start - 1.second).select { |time| time <= start + HORIZON }.map(&:to_i)
  end

  # Rewrites the row only if it still holds the text that was read, and records it. 1 when rewritten.
  def record_rewrite(table, id, old_text, new_text)
    changed = exec_update("UPDATE #{table} SET recurrence_rule = #{connection.quote(new_text)} " \
                          "WHERE id = #{Integer(id)} AND recurrence_rule = #{connection.quote(old_text)}")
    return 0 unless changed == 1

    execute("INSERT INTO recurrence_rule_rewrites (table_name, record_id, old_rule, new_rule, migration_version, created_at) " \
            "VALUES (#{connection.quote(table)}, #{Integer(id)}, #{connection.quote(old_text)}, #{connection.quote(new_text)}, #{connection.quote(RECORD_VERSION)}, now())")
    1
  end

  def restore(table)
    restored = exec_update(<<~SQL.squish)
      UPDATE #{table} SET recurrence_rule = r.old_rule
      FROM recurrence_rule_rewrites r
      WHERE r.table_name = #{connection.quote(table)} AND r.migration_version = #{connection.quote(RECORD_VERSION)}
        AND r.record_id = #{table}.id AND #{table}.recurrence_rule = r.new_rule
    SQL
    say "#{table}: #{restored} rules restored"
  end

  # Rewritten rules whose row still exists but no longer holds the rewritten text.
  def edited_count
    TABLES.sum do |table|
      select_value(<<~SQL.squish).to_i
        SELECT count(*) FROM recurrence_rule_rewrites r JOIN #{table} t ON t.id = r.record_id
        WHERE r.table_name = #{connection.quote(table)} AND r.migration_version = #{connection.quote(RECORD_VERSION)}
          AND t.recurrence_rule IS DISTINCT FROM r.new_rule
      SQL
    end
  end
end

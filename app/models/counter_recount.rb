# frozen_string_literal: true

require "csv"

# Compares the stored like counter of every repository and the stored vote counter of every comment with the rows
# behind them (likes; upvotes minus downvotes), and can write the counted values back. Every row it would change
# is listed first; applying records the old and the written value of each row in counter_recount_corrections, in
# the same transaction as the change, and also writes them to a CSV file for convenience.
class CounterRecount
  Difference = Struct.new(:kind, :id, :stored, :counted)

  LIKES_SQL = <<~SQL.squish
    SELECT 'like' AS kind, repositories.id, COALESCE(repositories."like", 0) AS stored, COUNT(likes.id) AS counted
    FROM repositories LEFT JOIN likes ON likes.repository_id = repositories.id
    GROUP BY repositories.id
    HAVING COALESCE(repositories."like", 0) <> COUNT(likes.id)
    ORDER BY repositories.id
  SQL

  VOTES_SQL = <<~SQL.squish
    SELECT 'upvote' AS kind, comments.id, COALESCE(comments.upvote, 0) AS stored,
           COALESCE(SUM(CASE WHEN upvotes.id IS NULL THEN 0 WHEN upvotes.downvote THEN -1 ELSE 1 END), 0) AS counted
    FROM comments LEFT JOIN upvotes ON upvotes.comment_id = comments.id
    GROUP BY comments.id
    HAVING COALESCE(comments.upvote, 0) <> COALESCE(SUM(CASE WHEN upvotes.id IS NULL THEN 0 WHEN upvotes.downvote THEN -1 ELSE 1 END), 0)
    ORDER BY comments.id
  SQL

  # Per kind: the table and column, and a subquery that counts the rows behind the counter of the row it is run for.
  KINDS = {
    "like" => { table: "repositories", column: "like", counted: <<~SQL.squish },
      SELECT COUNT(*) FROM likes WHERE likes.repository_id = repositories.id
    SQL
    "upvote" => { table: "comments", column: "upvote", counted: <<~SQL.squish }
      SELECT COALESCE(SUM(CASE WHEN upvotes.downvote THEN -1 ELSE 1 END), 0) FROM upvotes
      WHERE upvotes.comment_id = comments.id
    SQL
  }.freeze

  # Every counter whose stored value differs from the rows, ordered by kind and id.
  def differences
    [LIKES_SQL, VOTES_SQL].flat_map do |sql|
      ApplicationRecord.connection.select_rows(sql).map do |kind, id, stored, counted|
        Difference.new(kind, id.to_i, stored.to_i, counted.to_i)
      end
    end
  end

  # Sets each differing counter to the number counted now and records every change in counter_recount_corrections.
  # The row is locked first and counted inside the transaction, so the recorded new value is the one written and a
  # like or vote saved meanwhile waits for the lock. The changes are also written to the CSV file at +path+, which
  # is never overwritten. Returns the differences that were applied, with the values actually written.
  def apply!(path)
    run_at = Time.current
    CSV.open(path, "wx") do |csv|
      csv << %w[kind id stored counted]
      applied = ApplicationRecord.transaction { differences.filter_map { |difference| correct(difference, run_at) } }
      applied.each { |difference| csv << difference.to_a }
      applied
    end
  end

  private

  def correct(difference, run_at)
    kind = KINDS.fetch(difference.kind)
    stored, counted = lock_and_count(kind, difference.id)
    return if stored.to_i == counted.to_i

    write(kind, difference.id, counted)
    archive(kind, difference.id, stored, counted, run_at)
    Difference.new(difference.kind, difference.id, stored.to_i, counted.to_i)
  end

  def archive(kind, id, stored, counted, run_at)
    CounterRecountCorrection.create!(table_name: kind[:table], row_id: id, column_name: kind[:column],
                                     old_value: stored, new_value: counted, run_at: run_at)
  end

  def lock_and_count(kind, id)
    table, column = quoted(kind)
    sql = "SELECT #{table}.#{column}, (#{kind[:counted]}) FROM #{table} WHERE #{table}.id = ? FOR UPDATE"
    ApplicationRecord.connection.select_rows(ApplicationRecord.sanitize_sql_array([sql, id])).first
  end

  def write(kind, id, counted)
    table, column = quoted(kind)
    ApplicationRecord.connection.update(
      ApplicationRecord.sanitize_sql_array(["UPDATE #{table} SET #{column} = ? WHERE id = ?", counted.to_i, id])
    )
  end

  def quoted(kind)
    connection = ApplicationRecord.connection
    [connection.quote_table_name(kind[:table]), connection.quote_column_name(kind[:column])]
  end
end

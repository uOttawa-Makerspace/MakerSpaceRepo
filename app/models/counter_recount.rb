# frozen_string_literal: true

require "csv"

# Compares the stored like counter of every repository and the stored vote counter of every comment with the rows
# behind them (likes; upvotes minus downvotes), and can write the counted values back. Every row it would change
# is listed first; applying writes the old values to a CSV file before the first change.
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

  WRITES = {
    "like" => <<~SQL.squish,
      UPDATE repositories SET "like" = (SELECT COUNT(*) FROM likes WHERE likes.repository_id = repositories.id)
      WHERE repositories.id = ?
    SQL
    "upvote" => <<~SQL.squish
      UPDATE comments SET upvote = (
        SELECT COALESCE(SUM(CASE WHEN upvotes.downvote THEN -1 ELSE 1 END), 0) FROM upvotes
        WHERE upvotes.comment_id = comments.id)
      WHERE comments.id = ?
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

  # Writes the old values to +path+, then sets each listed counter to the number counted now. Returns the
  # differences that were applied.
  def apply!(path)
    found = differences
    write_csv(path, found)
    ApplicationRecord.transaction { found.each { |difference| write(difference) } }
    found
  end

  private

  def write_csv(path, found)
    CSV.open(path, "w") do |csv|
      csv << %w[kind id stored counted]
      found.each { |difference| csv << difference.to_a }
    end
  end

  # The value is counted again inside the statement, so a like or vote saved since the list was made is included.
  def write(difference)
    ApplicationRecord.connection.update(
      ApplicationRecord.sanitize_sql_array([WRITES.fetch(difference.kind), difference.id])
    )
  end
end

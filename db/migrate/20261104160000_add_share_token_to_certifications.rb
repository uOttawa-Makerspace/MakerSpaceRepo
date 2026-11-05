require Rails.root.join("lib/concurrent_index_builder")

# Gives every certification a random, URL-safe token for its public badge page, so a
# badge link no longer depends on the sequential id. The token is generated once and
# never changes (the model marks it read-only), so links already shared stay valid.
#
# Up:
#   1. adds certifications.share_token (string, nullable) unless it exists;
#   2. fills EVERY row where share_token IS NULL (active and inactive alike, raw SQL so
#      the model's default scope does not hide any) with SecureRandom.urlsafe_base64(16),
#      1000 rows per UPDATE. A token is never all digits, so a numeric path segment can
#      only mean an old id. Rows that already have a token are not touched, so a second
#      run changes nothing;
#   3. builds a unique index on share_token CONCURRENTLY (writes are not blocked).
#
# Down drops the index and the column. This loses nothing: the column and its index are
# created by this migration and nothing else depends on them yet. No existing column or
# row is read, changed or deleted by either direction.
class AddShareTokenToCertifications < ActiveRecord::Migration[8.1]
  include ConcurrentIndexBuilder
  disable_ddl_transaction!

  INDEX_NAME = "index_certifications_on_share_token"
  BATCH = 1000

  def up
    add_column_with_lock_timeout
    backfill_tokens
    add_index_concurrently :certifications, :share_token, name: INDEX_NAME, unique: true
  end

  def down
    remove_index :certifications, name: INDEX_NAME, algorithm: :concurrently, if_exists: true
    transaction do
      execute "SET LOCAL lock_timeout = '3s'"
      remove_column :certifications, :share_token if column_exists?(:certifications, :share_token)
    end
  end

  # Public so the fill can be exercised on its own.
  def backfill_tokens
    loop do
      ids = select_values("SELECT id FROM certifications WHERE share_token IS NULL ORDER BY id LIMIT #{BATCH}")
      break if ids.empty?

      tokens = ids.map { new_token }
      execute <<~SQL.squish
        UPDATE certifications SET share_token = v.token
        FROM (SELECT unnest(ARRAY[#{ids.map(&:to_i).join(',')}]) AS id,
                     unnest(ARRAY[#{tokens.map { |t| quote(t) }.join(',')}]) AS token) v
        WHERE certifications.id = v.id AND certifications.share_token IS NULL
      SQL
    end
  end

  private

  # The column change waits at most 3s for its table lock (the concurrent index build
  # is left without a timeout so a long-running transaction does not cancel it).
  def add_column_with_lock_timeout
    return if column_exists?(:certifications, :share_token)

    transaction do
      execute "SET LOCAL lock_timeout = '3s'"
      add_column :certifications, :share_token, :string
    end
  end

  def new_token
    loop do
      token = SecureRandom.urlsafe_base64(16)
      return token if token.match?(/\D/)
    end
  end
end

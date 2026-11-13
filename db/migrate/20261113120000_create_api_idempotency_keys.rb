# The Idempotency-Key a client sent with a create request, kept with the response it got, so a repeat
# of the same request by the same user is answered with that response instead of creating again.
# One row per (user, key): the unique index is what makes two concurrent repeats create only once.
# request_digest is the SHA-256 of the request body, to refuse a key reused for a different request.
# users.id is a serial (integer), so user_id is an integer. New table with no existing data; rolling
# back drops it.
class CreateApiIdempotencyKeys < ActiveRecord::Migration[8.1]
  def change
    create_table :api_idempotency_keys do |t|
      t.references :user, type: :integer, null: false, index: false, foreign_key: { on_delete: :cascade }
      t.string :key, null: false, limit: 255
      t.string :request_digest, null: false
      t.integer :response_status, null: false
      t.jsonb :response_body, null: false
      t.timestamps
      t.index %i[user_id key], unique: true
    end
  end
end

# Refresh tokens for /api/v1 (chunk 20b). Only the SHA-256 digest of the 32-byte
# random token is stored. Tokens rotate on use; a family (family_id) is the chain
# of tokens that descend from one login, so replaying an already-rotated token can
# revoke the whole chain. token_version is the user's at issue time: a bump
# (password change/reset, admin lock, soft delete) makes the token unusable.
# users.id is a serial (integer), so user_id is an integer. New table, reversible.
class CreateApiRefreshTokens < ActiveRecord::Migration[8.1]
  def change
    create_table :api_refresh_tokens do |t|
      t.references :user, type: :integer, null: false, foreign_key: { on_delete: :cascade }
      t.string :token_digest, null: false
      t.uuid :family_id, null: false
      t.integer :token_version, null: false, default: 0
      t.datetime :expires_at, null: false
      t.datetime :revoked_at
      t.bigint :replaced_by_id
      t.string :user_agent
      t.datetime :created_at, null: false
      t.datetime :last_used_at
    end
    add_index :api_refresh_tokens, :token_digest, unique: true
    add_index :api_refresh_tokens, :family_id
  end
end

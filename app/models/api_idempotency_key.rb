# frozen_string_literal: true

require "digest"

# An Idempotency-Key sent with an /api/v1 create request, stored with the response that request got
# (see doc/api/v1/README.md). A repeat with the same key by the same user is answered with the stored
# response; the same key with a different request is refused. Rows are kept: a key is a random value
# the client makes for one submission, so an old row only ever answers a repeat of that submission.
class ApiIdempotencyKey < ApplicationRecord
  MAX_LENGTH = 255

  belongs_to :user

  def self.acceptable?(key) = key.present? && key.length <= MAX_LENGTH

  # The request a key belongs to: method, path and body (object keys sorted, so key order does not matter).
  def self.digest_of(request)
    Digest::SHA256.hexdigest([request.method, request.path, canonical(request.request_parameters)].to_json)
  end

  def self.canonical(value)
    case value
    when Hash then value.keys.sort_by(&:to_s).to_h { |k| [k.to_s, canonical(value[k])] }
    when Array then value.map { |v| canonical(v) }
    else value
    end
  end
  private_class_method :canonical

  # Runs the block, which writes the result and returns the response body, and records the key with
  # that response in the same transaction. When another request already recorded the key (a concurrent
  # repeat waits here for it to commit), everything the block wrote is rolled back and this returns
  # false; the caller then answers with the recorded response.
  def self.record(user:, key:, digest:, status:)
    transaction do
      body = yield
      row = { user_id: user.id, key: key, request_digest: digest, response_status: status, response_body: body }
      # ON CONFLICT DO NOTHING: no row comes back when the key is already recorded
      inserted = insert(row, unique_by: %i[user_id key], returning: :id) # rubocop:disable Rails/SkipsModelValidations
      raise ActiveRecord::Rollback if inserted.none?

      true
    end || false
  end

  def same_request?(digest) = request_digest == digest
end

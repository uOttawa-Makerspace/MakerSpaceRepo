# frozen_string_literal: true

require "rails_helper"

# The table behind the Idempotency-Key of API creates: required columns, one row per user and key, and
# rows that go with their user.
RSpec.describe "api_idempotency_keys table" do
  let(:connection) { ActiveRecord::Base.connection }
  let(:user) { create(:user, :staff) }
  let(:row) { { user: user, key: "k", request_digest: "d", response_status: 201, response_body: { id: 1 } } }

  it "requires every column at the database" do
    columns = connection.columns(:api_idempotency_keys).to_h { |c| [c.name, c.null] }
    expect(columns.except("id").values).to all(eq(false))
  end

  it "refuses a second row for the same user and key even past the model" do
    ApiIdempotencyKey.create!(row)
    expect { ApiIdempotencyKey.new(row).save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    expect { ApiIdempotencyKey.create!(row.merge(user: create(:user, :staff))) }.not_to raise_error
  end

  it "has a foreign key to users that removes the rows with a hard-deleted user" do
    fk = connection.foreign_keys(:api_idempotency_keys).sole
    expect([fk.column, fk.to_table, fk.on_delete]).to eq(["user_id", "users", :cascade])
  end
end

# frozen_string_literal: true

require "rails_helper"

# The kiosk sign-in log table: foreign keys, required columns and an action check.
RSpec.describe "kiosk_sign_events table" do
  let(:connection) { ActiveRecord::Base.connection }
  let(:row) { { actor: create(:user, :staff), visitor: create(:user, :regular_user), space: create(:space), action: "sign_in", created_at: Time.zone.now } }

  it "requires actor, visitor, space, action and time at the database" do
    columns = connection.columns(:kiosk_sign_events).to_h { |c| [c.name, c.null] }
    expect(columns.slice("actor_id", "visitor_id", "space_id", "action", "created_at").values).to all(eq(false))
  end

  it "has foreign keys to users and spaces" do
    targets = connection.foreign_keys(:kiosk_sign_events).map { |f| [f.column, f.to_table] }
    expect(targets).to contain_exactly(%w[actor_id users], %w[visitor_id users], %w[space_id spaces])
  end

  it "has an index for listing by time" do
    expect(connection.indexes(:kiosk_sign_events).map(&:columns)).to include(["created_at"])
  end

  it "rejects an unknown action even past the model" do
    event = KioskSignEvent.new(row.merge(action: "bogus"))
    expect { event.save!(validate: false) }.to raise_error(ActiveRecord::StatementInvalid, /kiosk_sign_events_action_check/)
  end
end

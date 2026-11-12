require "rails_helper"
require Rails.root.join("db/migrate/20261112170000_add_shadowing_hours_to_google_calendar_pending_changes")

# DDL is transactional in PostgreSQL: each example runs the migration down (and up) inside its transaction.
RSpec.describe AddShadowingHoursToGoogleCalendarPendingChanges do
  let(:connection) { ActiveRecord::Base.connection }

  def migrate(direction)
    ActiveRecord::Migration.suppress_messages { described_class.new.public_send(direction) }
    GoogleCalendar::PendingChange.reset_column_information
  end

  def columns = connection.select_rows("SELECT id, action, event_id, google_event_id, calendar_id, attempts FROM google_calendar_pending_changes ORDER BY id")

  it "leaves the existing rows exactly as they were, down and up again" do
    GoogleCalendar::PendingChange.ask_push(7)
    GoogleCalendar::PendingChange.ask_removal(8, "aaa", "cal")
    before = columns

    migrate(:down)
    expect(columns).to eq(before)
    migrate(:up)
    expect(columns).to eq(before)
  end

  it "refuses to roll back while a shadowing shift change is waiting, and deletes nothing" do
    GoogleCalendar::PendingChange.ask_push(7)
    GoogleCalendar::PendingChange.ask_shadow_push(create(:shadowing_hour).id)

    expect { migrate(:down) }.to raise_error(ActiveRecord::IrreversibleMigration, /1 shadowing shift calendar change/)
    expect(GoogleCalendar::PendingChange.count).to eq(2)
  end

  it "takes the old shape again after down: an event is required and shadow_push is not an action" do
    migrate(:down)
    expect { connection.execute("INSERT INTO google_calendar_pending_changes (action, attempts, created_at, updated_at) VALUES ('push', 0, now(), now())") }
      .to raise_error(ActiveRecord::NotNullViolation)
  end
end

class AddGoogleEventIdToShifts < ActiveRecord::Migration[6.0]
  def change
    add_column :shifts, :google_event_id, :string
  end
end

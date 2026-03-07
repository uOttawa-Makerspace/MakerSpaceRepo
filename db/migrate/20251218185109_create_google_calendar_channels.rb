class CreateGoogleCalendarChannels < ActiveRecord::Migration[7.2]
  def change
    create_table :google_calendar_channels do |t|
      t.string :channel_id, null: false
      t.string :resource_id, null: false
      t.datetime :expires_at, null: false

      t.timestamps
    end

    add_index :google_calendar_channels, :channel_id, unique: true
  end
end

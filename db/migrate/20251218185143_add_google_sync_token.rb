class AddGoogleSyncToken < ActiveRecord::Migration[7.2]
  def change
    add_column :google_calendar_channels, :sync_token, :string
  end
end
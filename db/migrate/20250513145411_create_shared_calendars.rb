class CreateSharedCalendars < ActiveRecord::Migration[7.2]
  def change
    create_table :shared_calendars do |t|
      t.string :name
      t.string :url
      t.references :space, null: false, foreign_key: { to_table: :"public.spaces" }

      t.timestamps
    end
  end
end

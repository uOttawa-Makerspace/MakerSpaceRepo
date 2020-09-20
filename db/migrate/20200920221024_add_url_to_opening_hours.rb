class AddUrlToOpeningHours < ActiveRecord::Migration[6.0]
  def change
    add_column :opening_hours, :url, :string
  end
end

class AddPreviousMeanToPopularHours < ActiveRecord::Migration[6.0]
  def change
    add_column :popular_hours, :previous_mean, :float, default: 0
  end
end

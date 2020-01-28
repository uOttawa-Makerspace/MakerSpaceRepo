class AddLevelToCertification < ActiveRecord::Migration
  def change
    add_column :certifications, :level, :string, default: "Beginner"
  end
end

class AddDemotionReasonToCertifications < ActiveRecord::Migration[6.0]
  def change
    add_column :certifications, :demotion_reason, :string
  end
end

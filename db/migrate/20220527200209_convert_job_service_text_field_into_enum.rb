class ConvertJobServiceTextFieldIntoEnum < ActiveRecord::Migration[6.1]
  def change
    change_column :job_service_groups, :text_field, :boolean, default: nil
    change_column :job_service_groups, :text_field, :integer,default: 0, using: 'case when text_field then 1::integer else 0::integer end'
  end
end

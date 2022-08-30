class ConvertJobServiceTextFieldIntoEnum < ActiveRecord::Migration[6.1]
  def up
    change_column :job_service_groups, :text_field, :boolean, default: nil
    change_column :job_service_groups,
                  :text_field,
                  :integer,
                  default: 0,
                  using:
                    "case when text_field then 1::integer else 0::integer end"
    JobServiceGroup.where(name: %w[PLA ABS]).update(text_field: :option)
  end

  def down
    change_column :job_service_groups, :text_field, :integer, default: nil
    change_column :job_service_groups,
                  :text_field,
                  :boolean,
                  default: 0,
                  using: "case when text_field = 1 then true else false end"
  end
end

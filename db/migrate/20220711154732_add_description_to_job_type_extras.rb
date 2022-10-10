class AddDescriptionToJobTypeExtras < ActiveRecord::Migration[6.1]
  def change
    add_column :job_type_extras, :description, :string

    reversible do |change|
      change.up do
        JobTypeExtra.find_by(name: "Machine Costs").update(
          description:
            "10$/h for vector (cut) and 24$/h for vector and raster (cut and engraving)"
        )
      end
    end
  end
end

class RenameNameToNameEnInTrainings < ActiveRecord::Migration[7.2]
  change_table :trainings do |t|
    t.rename :name, :name_en
  end

end

class RemoveLevelFromNameFrInTrainings < ActiveRecord::Migration[7.2]
  def up
    Training.all.each do |t|
      t.update(name_fr: t.name_fr.split('-').last) unless t.name_fr.nil?
    end 
  end
end

class SplitDescriptionTrainings < ActiveRecord::Migration[7.2]
  def up
    Training.all.each do |t|
      t.update(description_fr: t.description_en.split('||').last)
      t.update(description_en: t.description_en.split('||').first)
    end 
  end

  def down
    Training.all.each do |t|
      t.update(description_en: "#{t.description_en}||#{t.description_fr}")
    end
  end
end

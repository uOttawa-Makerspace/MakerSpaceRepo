class AddLevelToCertification < ActiveRecord::Migration[7.2]
  def up
    add_column :certifications, :level, :string
    Certification.all.each do |c|
      c.update(level: c.training_session.level) unless c.training_session.level.nil?
    end 
  end
end

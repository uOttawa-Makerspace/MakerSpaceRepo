class LabSession < ActiveRecord::Base
  belongs_to :user

  def create_array                  
    labs = LabSession.all    
    column = []             
    labs.each do |lab|       
      row = []              
      row << lab.id        
      user = lab.user       
      row << user.name << user.email << user.faculty     
      column << row         
    end                     
    column                  
  end

  def to_csv
  	attributes = create_array

    CSV.generate do |csv|
      attributes.each do |row|
        csv << row
      end
    end
  end                       

end

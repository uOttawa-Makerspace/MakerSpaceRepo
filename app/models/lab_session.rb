class LabSession < ApplicationRecord
  belongs_to :user
  belongs_to :space

  scope :between_dates_picked, ->(start_date , end_date){ where('created_at BETWEEN ? AND ? ', start_date , end_date) }

  def self.to_csv (attributes)
    CSV.generate do |csv|
      attributes.each do |row|
        csv << row
      end
    end
  end

end

class LabSession < ApplicationRecord
  belongs_to :user
  belongs_to :pi_reader
  has_one :space, through: :pi_reader

  scope :in_last_month, -> { where('sign_in_time BETWEEN ? AND ? ', 1.month.ago.beginning_of_month , 1.month.ago.end_of_month) }

  def self.to_csv (attributes)
    CSV.generate do |csv|
      attributes.each do |row|
        csv << row
      end
    end
  end

end

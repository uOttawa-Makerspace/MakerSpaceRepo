class Rfid < ActiveRecord::Base
  belongs_to :user

  validates :card_number, 
    presence: { message: "Card number is required." },
    uniqueness: { message: "Card number is already in use." }
end

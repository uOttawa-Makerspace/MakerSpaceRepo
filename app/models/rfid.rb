class Rfid < ActiveRecord::Base
  belongs_to :user

  scope :recent_unset, -> {
    where(user: nil).order("created_at desc")
  }

  validates :card_number,
    presence: { message: "Card number is required." },
    uniqueness: { message: "Card number is already in use." }
end

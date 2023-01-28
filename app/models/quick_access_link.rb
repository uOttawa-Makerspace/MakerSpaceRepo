class QuickAccessLink < ApplicationRecord
  belongs_to :user

  validates :name, presence: true
  validates :path, presence: true
  validates :path,
            uniqueness: {
              scope: :user_id,
              message: "You already have a quick access link to that location"
            }
end

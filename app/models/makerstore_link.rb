class MakerstoreLink < ApplicationRecord
  validates :title, :url, :image, presence: true
  has_one_attached :image

  default_scope -> { order(order: :ASC) }
end

class MakerstoreLink < ApplicationRecord
  validates :title, :url, :image_url, presence: true
  has_one_attached :image
end

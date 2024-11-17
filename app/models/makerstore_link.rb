class MakerstoreLink < ApplicationRecord
  validates :title, :url, :image_url, presence: true
end

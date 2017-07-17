class CategoryOption < ActiveRecord::Base
  belongs_to :admin
  has_many :categories
  has_many :repositories, through: :categories

  validates :name, presence: true, uniqueness: true
  scope :show_options, -> { order("lower(name) ASC").all }

end

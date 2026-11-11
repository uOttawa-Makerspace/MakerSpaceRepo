class CategoryOption < ApplicationRecord
  belongs_to :admin, optional: true
  has_many :categories
  validates :name, presence: true
  def in_use?
    categories.exists?
  end

  scope :show_options, -> { order(Arel.sql("lower(name) ASC")).all }
end

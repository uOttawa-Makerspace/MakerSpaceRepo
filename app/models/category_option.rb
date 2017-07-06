class CategoryOption < ActiveRecord::Base
  belongs_to :admin
  validates :name, presence: true, uniqueness: true
  scope :show_options, -> { order("lower(name) ASC").all }

  def repositories
    return Repository.joins(:categories).where(categories: { category_option_id: self.id })
  end

end

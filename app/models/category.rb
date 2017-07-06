class Category < ActiveRecord::Base
  belongs_to :repository
  belongs_to :category_option

  def name
    return self.category_option.name
  end

end

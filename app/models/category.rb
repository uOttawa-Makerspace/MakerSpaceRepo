class Category < ApplicationRecord
  belongs_to :repository
  belongs_to :category_option

end

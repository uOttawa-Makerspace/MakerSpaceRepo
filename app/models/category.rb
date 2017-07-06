class Category < ActiveRecord::Base
  belongs_to :repository
  belongs_to :category_option
end

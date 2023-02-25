class Category < ApplicationRecord
  belongs_to :repository, optional: true
  belongs_to :category_option, optional: true
  belongs_to :project_proposal, optional: true
end

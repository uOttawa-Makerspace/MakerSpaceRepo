class Equipment < ApplicationRecord
  belongs_to :repository, optional: true
end

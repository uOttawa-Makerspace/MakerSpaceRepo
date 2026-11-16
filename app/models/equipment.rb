class Equipment < ApplicationRecord
  belongs_to :repository, -> { including_hidden }, optional: true
end

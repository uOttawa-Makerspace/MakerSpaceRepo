class Training < ActiveRecord::Base
  validates :name, presence: true
end

class AreaOption < ActiveRecord::Base
  validates :name, presence: true
  scope :show_options, -> { order("lower(name) ASC").all }
end

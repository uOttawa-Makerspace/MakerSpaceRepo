class CourseOption < ActiveRecord::Base
  validates :title, presence: true, uniqueness: true
  validates :code, presence: true, uniqueness: true
  scope :show_options, -> { order("lower(code) ASC").all }
end

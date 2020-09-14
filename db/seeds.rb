# frozen_string_literal: true
#
OrderStatus.find_or_create_by(id: 1, name: 'In progress')
OrderStatus.find_or_create_by(id: 2, name: 'Completed')
["GNG2101", "GNG2501", "GNG1103", "GNG1503", "MCG4143", "no course"].each do |course_name|
  CourseName.find_or_create_by(name: course_name)
end
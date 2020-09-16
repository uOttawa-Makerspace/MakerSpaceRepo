# frozen_string_literal: true

# This file should contain all the record creation needed to seed the database with its default values.
# The data can then be loaded with the rake db:seed (or created alongside the db with db:setup).
#
# Examples:
#
#   cities = City.create([{ name: 'Chicago' }, { name: 'Copenhagen' }])
#   Mayor.create(name: 'Emanuel', city: cities.first)
OrderStatus.create(id: 1, name: 'In progress')
OrderStatus.create(id: 2, name: 'Completed')



# Creating Spaces
['Makerspace', 'MTC', 'Brunsfield Center', 'PITS', 'Makerlab 121', 'Makerlab 119', 'Sandbox', 'CEED'].each do |space_name|
  Space.find_or_create_by(name: space_name)
end

#Creating all popular Hours
Space.all.each do |space|
  (0..6).each do |weekday|
    (0..23).each do |hour|
      PopularHour.find_or_create_by(space_id: space.id, hour: hour, day: weekday)
    end
  end
end
# frozen_string_literal: true
#
["GNG2101", "GNG2501", "GNG1103", "GNG1503", "MCG4143", "no course"].each do |course_name|
  CourseName.find_or_create_by(name: course_name)
end
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

#Skills type:
['Machine Shop', 'Technical', 'Soft'].each do |skill_type_name|
  Skill.create(name: skill_type_name)
end

# Training description and skill types link
machine_trainings = ['Basic Training', 'Lathe', 'MIG Welding', 'Mill', 'TIG Welding']
technical_trainings = ['3D Printing', '3D Printing Advanced', '3D scanning', 'Advanced Arduino',
                       'Arduino Basics', 'Basic Java', 'Embroidery', 'Introduction Coding in Virtual Reality',
                       'Introduction to Fusion360 CAD', 'Laser Cutting', 'Laser Cutting Advanced', 'PCB Design',
                       'Soldering', 'VR - Basic Training']
soft_trainings = ['COVID Returning to Work on Campus Training', 'General Safety', 'Makerspace Volunteer', 'Shadowing']
Training.all.each do |training|
  training.description = training.name
  skill_type = Proc.new{ |skill_name| Skill.find_by(name: skill_name) }
  if machine_trainings.include?(training.name)
    training.skill = skill_type.call('Machine Shop')
  elsif technical_trainings.include?(training.name)
    training.skill = skill_type.call('Technical')
  elsif soft_trainings.include?(training.name)
    training.skill = skill_type.call('Soft')
  end
  training.save
end

# Drop-off locations
['MTC', 'Makerspace'].each do |location_name|
  DropOffLocation.create(name: location_name)
end
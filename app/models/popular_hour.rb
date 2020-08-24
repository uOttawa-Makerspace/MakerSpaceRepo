class PopularHour < ApplicationRecord

  def self.generate_data
    data = Hash.new()
    Space.all.each do |space|
      data[space.name] = Hash.new()
      (0..6).each do |weekday|
        data[space.name][weekday] = []
        (0..23).each do |hour|
          if PopularHour.where(space_id: space.id, hour: hour, day: weekday).present?
            data[space.name][weekday].push(PopularHour.where(space_id: space.id, hour: hour, day: weekday).first.mean)
          else
            data[space.name][weekday].push(PopularHour.create(space_id: space.id, hour: hour, day: weekday, count: 0, mean: 0).mean)
          end
        end
      end
    end
    data
  end

end

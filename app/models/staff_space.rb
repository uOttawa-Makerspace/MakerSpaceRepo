class StaffSpace < ApplicationRecord
  belongs_to :user
  belongs_to :space

  before_create :create_color
  before_save :check_color

  # List of colors with good enough contrast between them
  $color_list = %w[#e6194b #3cb44b #ffe119 #4363d8 #f58231 #911eb4 #46f0f0 #f032e6 #bcf60c #fabebe #008080 #e6beff #9a6324 #fffac8 #800000 #aaffc3 #808000 #ffd8b1 #000075 #808080 #ffffff #000000]

  def create_color
    self.color = generate_color;
  end

  def check_color
    self.color = generate_color if self.color.nil?
  end

  def generate_color
    not_available_colors = StaffSpace.all.where(space: space).pluck(:color)
    if ($color_list - not_available_colors).empty?
      "#" + "%06x" % (staff.user.id.hash & 0xffffff)
    else
      ($color_list - not_available_colors)[0]
    end
  end
end

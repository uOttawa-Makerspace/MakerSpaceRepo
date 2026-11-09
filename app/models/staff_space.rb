class StaffSpace < ApplicationRecord
  belongs_to :user, optional: true
  belongs_to :space, optional: true

  COLOR_FORMAT = /\A#\h{6}\z/

  normalizes :color, with: ->(color) { color.strip.downcase }

  # The colour is written into style attributes by the calendar pages, so only a #rrggbb value is accepted. A
  # stored value is only checked when it changes, so an older row stays editable for its other fields.
  validates :color, format: { with: COLOR_FORMAT }, allow_blank: true, if: :will_save_change_to_color?

  before_save :ensure_color

  # List of colors with good enough contrast between them
  $color_list = %w[
    #e6194b
    #3cb44b
    #ffe119
    #4363d8
    #f58231
    #911eb4
    #46f0f0
    #f032e6
    #bcf60c
    #fabebe
    #008080
    #e6beff
    #9a6324
    #fffac8
    #800000
    #aaffc3
    #808000
    #ffd8b1
    #000075
    #808080
    #ffffff
    #000000
  ]

  # A colour passed in is kept; a blank one gets the first palette entry still free in the space.
  def ensure_color
    self.color = generate_color if color.blank?
  end

  def generate_color
    not_available_colors = StaffSpace.all.where(space: space).pluck(:color)
    if ($color_list - not_available_colors).empty?
      "#" + "%06x" % (self.user_id.hash & 0xffffff)
    else
      ($color_list - not_available_colors)[0]
    end
  end
end

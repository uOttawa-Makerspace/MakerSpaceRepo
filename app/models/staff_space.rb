class StaffSpace < ApplicationRecord
  belongs_to :user, optional: true
  belongs_to :space, optional: true

  COLOR_FORMAT = /\A#\h{6}\z/
  PLANNING_HORIZON = 4.weeks # how far ahead the event dialog ranks the staff for a planned event

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

  # Each staff member's calendar colour in a space, by user id.
  def self.colors_in(space_id) = where(space_id: space_id).pluck(:user_id, :color).to_h

  # The staff whose unavailabilities a space's calendar shows: its staff and admins.
  def self.calendar_staff(space_id) = User.where(id: where(space_id: space_id).select(:user_id), role: %w[admin staff])

  # The calendar staff of a space as the admin calendar sidebar lists them (id, name, colour, busy): those with
  # unavailabilities (stored, or an external calendar link) first, each part by name.
  def self.calendar_sidebar(space_id)
    colors = colors_in(space_id)
    staff = calendar_staff(space_id)
    busy = staff.where(id: StaffUnavailability.select(:user_id)).or(staff.where(id: StaffExternalUnavailability.select(:user_id))).ids
    staff.pluck(:id, :name).map { |id, name| { id: id, name: name, color: colors[id], busy: busy.include?(id) } }
         .sort_by { |member| [member[:busy] ? 0 : 1, member[:name].to_s.downcase] }
  end

  # The staff ranked (conflicts) for an event planned at the times of `window`, repeating by `rule` (nil: once).
  def self.conflicts_for(space_id, rule:, window:)
    proposal = RecurringSeries.new(rule: rule, starts_at: window.from, ends_at: window.to)
    conflicts(space_id, proposal.occurrences_in(CalendarWindow.new(window.from, window.from + PLANNING_HORIZON)))
  end

  # The calendar staff of a space for an event proposed at `occurrences`, each with the starts of those they are
  # unavailable for (StaffUnavailability.clashes): available first, each part by name (accents read as their letter).
  def self.conflicts(space_id, occurrences)
    colors = colors_in(space_id)
    staff = calendar_staff(space_id).to_a
    clashes = StaffUnavailability.clashes(staff, occurrences)
    rows = staff.map do |member|
      starts = clashes.fetch(member.id, []).map { |clash| clash.starts_at.utc.iso8601 }
      { id: member.id, name: member.name, color: colors[member.id], unavailableStarts: starts }
    end
    rows.sort_by { |row| I18n.transliterate(row[:name].to_s).downcase }.partition { |row| row[:unavailableStarts].empty? }.flatten(1)
  end

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

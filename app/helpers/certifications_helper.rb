# frozen_string_literal: true

module CertificationsHelper
  CERTIFICATION_LEVELS = {
    'Advanced' => {
      color: 'red',
      icon: '🦅'
    },
    'Intermediate' => {
      color: '#969600',
      icon: '🦩'
    },
    'Beginner' => {
      color: 'green',
      icon: '🦆'
    }
  }.freeze

  def certification_status(level)
    config = CERTIFICATION_LEVELS.fetch(level, { color: 'black', icon: '🐥' })
    label = level.presence || 'Newbie'

    content_tag(
      :span,
      "#{config[:icon]} #{label}",
      style: "color: #{config[:color]}; white-space: nowrap"
    )
  end
end

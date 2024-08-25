class OpeningHour < ApplicationRecord
  belongs_to :contact_info, optional: true

  def formatted(field)
    tag_map = I18n.t("hours").transform_keys { |k| "[#{k.upcase}]" }
    formatted = self[field]
    tag_map.each { |tag, value| formatted.gsub!(tag, value) }
    formatted
  end
end

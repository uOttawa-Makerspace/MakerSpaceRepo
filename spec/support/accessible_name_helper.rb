# frozen_string_literal: true

# Finds form controls that have no accessible name in a rendered HTML page:
# no <label for>, no wrapping <label>, no aria-label, no aria-labelledby that
# points at an element with text. Hidden, submit, button, reset and image
# inputs are ignored (buttons are named by their value or content).
module AccessibleNameHelper
  UNNAMED_INPUT_TYPES = %w[hidden submit button reset image].freeze

  def unnamed_fields(html)
    doc = Nokogiri::HTML(html)
    doc.css("input, select, textarea").reject { |el| named?(doc, el) }.map { |el| describe_field(el) }
  end

  private

  def named?(doc, field)
    return true if UNNAMED_INPUT_TYPES.include?(field["type"].to_s.downcase)
    return true if field["aria-label"].to_s.strip.present?
    return true if labelled_by_text?(doc, field["aria-labelledby"])
    return true if field.ancestors("label").any?

    id = field["id"].to_s
    id.present? && doc.css("label").any? { |label| label["for"] == id && label.text.strip.present? }
  end

  def labelled_by_text?(doc, ids)
    ids.to_s.split.any? { |id| doc.at_css("##{id}")&.text.to_s.strip.present? }
  end

  def describe_field(field)
    "<#{field.name} type=#{field['type'].inspect} id=#{field['id'].inspect} name=#{field['name'].inspect}>"
  end
end

RSpec.configure { |config| config.include AccessibleNameHelper }

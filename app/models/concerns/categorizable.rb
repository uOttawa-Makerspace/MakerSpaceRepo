# frozen_string_literal: true

# A record people tag with up to five categories, by name (repositories and project proposals).
module Categorizable
  extend ActiveSupport::Concern

  CATEGORY_LIMIT = 5

  included do
    has_many :categories, dependent: :destroy
  end

  # Saves the edit, then replaces the categories, in one transaction. A refused edit changes nothing.
  def update_with_categories(attributes, category_names)
    transaction do
      next false unless update(attributes)

      replace_categories(category_names)
      true
    end
  end

  # Blank names are skipped and only the first five are kept.
  def replace_categories(category_names)
    categories.destroy_all
    Array(category_names).compact_blank.first(CATEGORY_LIMIT).each { |name| categories.create!(name: name) }
  end
end

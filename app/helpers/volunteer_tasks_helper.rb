# frozen_string_literal: true

module VolunteerTasksHelper
  TASK_CATEGORY_KEYS = { "Events" => :events, "Projects" => :projects, "Supervising" => :supervising,
                         "Workshops" => :workshops, "Other" => :other }.freeze

  # A task category in the current language. A category outside the form's list is shown as +text+.
  def task_category_name(category, text = category.to_s)
    key = TASK_CATEGORY_KEYS[category.to_s]
    key ? t(key, scope: "volunteer_area.tasks.categories") : text
  end

  # Select options that show each category in the current language and submit its stored name.
  def task_category_options(categories)
    categories.map { |category| [task_category_name(category), category] }
  end
end

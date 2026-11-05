# frozen_string_literal: true

# The first path segment of every static route (admin, search, faq, ...). A
# profile lives at /:username, so a user with one of these names would have a
# page that an earlier route captures. The list is read from the routes, so it
# follows them when routes are added or removed.
module ReservedUsernames
  module_function

  def all
    @all ||= first_segments.to_set.freeze
  end

  def include?(username)
    all.include?(username.to_s.downcase)
  end

  def reset!
    @all = nil
  end

  def first_segments
    Rails.application.routes.routes.filter_map do |route|
      segment = route.path.spec.to_s.delete_prefix('/').split('/').first.to_s.sub(/\(.*/, '').downcase
      segment unless segment.empty? || segment.start_with?(':', '*')
    end.uniq
  end
end

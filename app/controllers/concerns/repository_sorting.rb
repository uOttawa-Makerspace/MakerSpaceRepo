# frozen_string_literal: true

# The sort options of a repository listing (?sort=...), as an order for the query. Newest first when the
# sort is missing or unknown.
module RepositorySorting
  extend ActiveSupport::Concern

  SORT_ORDERS = {
    "newest" => %i[created_at desc],
    "most_likes" => %i[like desc],
    "most_makes" => %i[make desc],
    "recently_updated" => %i[updated_at desc]
  }.freeze

  included { helper_method :sort_key }

  private

  # The sort applied: the requested one when it is known, newest otherwise.
  def sort_key
    SORT_ORDERS.key?(params[:sort]) ? params[:sort] : "newest"
  end

  def sort_order
    SORT_ORDERS.fetch(sort_key)
  end
end

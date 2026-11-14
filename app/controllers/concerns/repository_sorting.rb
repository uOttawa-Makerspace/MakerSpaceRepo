# frozen_string_literal: true

# The sort options of a repository listing (?sort=...), as an order for the query. Newest first when the
# sort is missing or unknown.
module RepositorySorting
  SORT_ORDERS = {
    "newest" => %i[created_at desc],
    "most_likes" => %i[like desc],
    "most_makes" => %i[make desc],
    "recently_updated" => %i[updated_at desc]
  }.freeze

  private

  def sort_order
    SORT_ORDERS.fetch(params[:sort], SORT_ORDERS["newest"])
  end
end

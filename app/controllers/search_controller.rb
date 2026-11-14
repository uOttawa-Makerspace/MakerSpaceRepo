# frozen_string_literal: true

class SearchController < SessionsController
  before_action :current_user
  before_action :no_container
  before_action :set_query

  SEARCH_SORT_BY_OPTIONS = %i[
    newest
    most_likes
    most_makes
    recently_updated
  ].freeze

  def explore
    scope = in_requested_categories(Repository.public_repos.with_card_data.order([sort_order].to_h))

    @pagy, @repositories = pagy(scope, limit: 12)
  end

  def search
    scope = Repository.public_repos.with_card_data

    scope = scope.fuzzy_search(@query) if @query

    scope = scope.order([sort_order].to_h)

    if signed_in? && params[:liked].present?
      scope = scope.includes(:likes).where(likes: { user_id: @user.id })
    end

    scope = in_requested_categories(scope)

    @pagy, @repositories = pagy(scope, limit: 12)

    # Shim the explore page
    render :explore
  end

  def category
    @pagy, @repositories = pagy(order_category_repos(category_repos(params[:slug])), limit: 12)
    @photos = photo_hash
  end

  def equipment
    sort_arr = sort_order
    name = params[:slug].to_s.tr("-", " ")

    repos = Repository
              .public_repos
              .with_card_data
              .where(id: Equipment.where(name: name).select(:repository_id))
              .to_a
              .sort_by { |s| -s[sort_arr.first].to_i }

    @pagy, @repositories = pagy(repos, limit: 12)
    @photos = photo_hash
  end

  private

  # The search text as a plain string without NUL bytes; nil when it is
  # missing, blank, or sent as an array or hash.
  def set_query
    @query = params[:q].delete("\u0000").presence if params[:q].is_a?(String)
  end

  # Limits the scope to the categories named by the `category` slugs. Slugs
  # that are unknown, or params that are not strings, are ignored; when none
  # is known the result is empty, like the category and equipment pages.
  def in_requested_categories(scope)
    return scope if params[:category].blank?

    names = SLUG_TO_CATEGORY_MODEL.values_at(*Array.wrap(params[:category]).grep(String)).compact
    return scope.none if names.empty?

    scope.includes(:categories).where(categories: { name: names })
  end

  # The public repositories filed under a category slug: by the legacy category column, by a category of the
  # slug's name, and by a category linked to the category option of that name; each repository once.
  def category_repos(slug)
    name = SLUG_TO_CATEGORY_MODEL[slug]
    (legacy_category_repos(SLUG_TO_OLD_CATEGORY[slug]) + named_category_repos(name) +
      category_option_repos(CategoryOption.find_by(name: name))).compact.uniq
  end

  def legacy_category_repos(category)
    return [] unless category

    Repository.public_repos.with_card_data.where(category: category).distinct
  end

  def named_category_repos(name)
    return [] unless name

    Repository.public_repos.with_card_data.where(
      id: Category.where(name: name).where.not(repository_id: nil).select(:repository_id)
    ).to_a
  end

  def category_option_repos(category_option)
    return [] unless category_option

    Repository.public_repos.with_card_data.where(
      id: Category.where(category_option_id: category_option.id).select(:repository_id)
    ).to_a
  end

  # Featured repositories only, most recently updated first, when asked; otherwise every one in the sort order.
  def order_category_repos(repos)
    return repos.select(&:featured?).sort_by(&:updated_at).reverse if params["featured"]

    sort_column = sort_order.first
    repos.sort_by { |s| -s[sort_column].to_i }
  end

  def sort_order
    case params[:sort]
    when "newest"
      %i[created_at desc]
    when "most_likes"
      %i[like desc]
    when "most_makes"
      %i[make desc]
    when "recently_updated"
      %i[updated_at desc]
    else
      %i[created_at desc]
    end
  end

  def photo_hash
    repository_ids = @repositories.map(&:id)
    photo_ids =
      Photo
        .where(repository_id: repository_ids)
        .group(:repository_id)
        .minimum(:id)

    photos = photo_ids.present? ? Photo.find(photo_ids.values) : []
    photos.each_with_object({}) { |e, h| h[e.repository_id] = e }
  end

  SLUG_TO_OLD_CATEGORY = {
    "internet-of-things" => "Internet of Things",
    "virtual-reality" => "Virtual Reality",
    "health-sciences" => "Bio-Medical",
    "mobile-development" => "Mobile",
    "other-projects" => "3D-Model",
    "wearable" => "Wearables"
  }.freeze

  SLUG_TO_CATEGORY_MODEL = {
    "internet-of-things" => "Internet of Things",
    "course-related-projects" => "Course-related Projects",
    "gng2101/gng2501" => "GNG2101/GNG2501",
    "gng1103/gng1503" => "GNG1103/GNG1503",
    "health-sciences" => "Health Sciences",
    "wearable" => "Wearable",
    "mobile-development" => "Mobile Development",
    "virtual-reality" => "Virtual Reality",
    "other-projects" => "Other Projects",
    "uottawa-team-projects" => "uOttawa Team Projects"
  }.freeze
end

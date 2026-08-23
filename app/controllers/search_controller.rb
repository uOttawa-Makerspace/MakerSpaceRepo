# frozen_string_literal: true

class SearchController < SessionsController
  before_action :current_user
  before_action :no_container

  SEARCH_SORT_BY_OPTIONS = %i[
    newest
    most_likes
    most_makes
    recently_updated
  ].freeze

  def explore
    scope = Repository.public_repos.order([sort_order].to_h)

    if params[:category].present?
      category_name = SLUG_TO_CATEGORY_MODEL[params[:category]]
      scope = scope.includes(:categories).where(categories: { name: category_name })
    end

    @pagy, @repositories = pagy(scope, limit: 12)
  end

  def search
    scope = Repository.public_repos
                      .includes(:users, :owner)
                      .includes(photos: { image_attachment: :blob })
                      .includes(repo_files: { file_attachment: :blob })

    if params[:q].present?
      scope = scope.fuzzy_search(params[:q])
    end

    scope = scope.order([sort_order].to_h)

    if signed_in? && params[:liked].present?
      scope = scope.includes(:likes).where(likes: { user_id: @user.id })
    end

    if params[:category].present?
      category_names = SLUG_TO_CATEGORY_MODEL.values_at(*params[:category])
      scope = scope.includes(:categories).where(categories: { name: category_names })
    end

    @pagy, @repositories = pagy(scope, limit: 12)

    # Shim the explore page
    render :explore
  end

  def category
    sort_arr = sort_order

    repos1 =
      if (category = SLUG_TO_OLD_CATEGORY[params[:slug]])
        Repository.where(category: category).distinct
      else
        []
      end

    repos2 =
      if (name = SLUG_TO_CATEGORY_MODEL[params[:slug]])
        Category
          .where(name: name)
          .where.not(repository_id: nil)
          .distinct
          .includes(:repository)
          .map(&:repository)
      else
        []
      end

    repos3 =
      if (category_option = CategoryOption.find_by(name: name))
        Category
          .where(category_option_id: category_option.id)
          .distinct
          .includes(:repository)
          .map(&:repository)
      else
        []
      end

    all_repos = (repos1 + repos2 + repos3).compact.uniq

    all_repos = if params["featured"]
                  all_repos.select(&:featured?).sort_by(&:updated_at).reverse
                else
                  all_repos.sort_by { |s| -s[sort_arr.first].to_i }
                end

    @pagy, @repositories = pagy(all_repos, limit: 12)
    @photos = photo_hash
  end

  def equipment
    sort_arr = sort_order
    name = params[:slug].to_s.tr("-", " ")

    repos = Equipment
              .where(name: name)
              .distinct
              .includes(:repository)
              .map(&:repository)
              .compact
              .uniq
              .sort_by { |s| -s[sort_arr.first].to_i }

    @pagy, @repositories = pagy(repos, limit: 12)
    @photos = photo_hash
  end

  private

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

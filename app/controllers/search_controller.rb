# frozen_string_literal: true

class SearchController < SessionsController
  before_action :current_user

  def explore
    if params[:category].blank?
      @repositories =
        Repository
          .paginate(per_page: 12, page: params[:page])
          .public_repos
          .order([sort_order].to_h).page params[:page]
    else
      @repositories =
        Repository
          .paginate(per_page: 12, page: params[:page])
          .public_repos
          .includes(:categories)
          .where(
            { categories: { name: SLUG_TO_CATEGORY_MODEL[params[:category]] } }
          )
          .order([sort_order].to_h).page params[:page]
    end
    @photos = photo_hash
  end

  def search
    sort_arr = sort_order
    if params[:category].blank?
      @repositories =
        Repository
          .paginate(per_page: 12, page: params[:page])
          .public_repos
          .order([sort_arr].to_h)
    else
      @repositories =
        Repository
          .paginate(per_page: 12, page: params[:page])
          .public_repos
          .includes(:categories)
          .where(
            { categories: { name: SLUG_TO_CATEGORY_MODEL[params[:category]] } }
          )
          .order([sort_order].to_h)
    end
    if params[:q].present?
      @repositories = @repositories.fuzzy_search(params[:q])
    end
    @photos = photo_hash
    # Shim the explore page
    render :explore
  end

  def category
    sort_arr = sort_order

    @repositories1 =
      if category = SLUG_TO_OLD_CATEGORY[params[:slug]]
        Repository.where(category: category).distinct
      else
        []
      end

    if name = SLUG_TO_CATEGORY_MODEL[params[:slug]]
      @repositories2 =
        Category
          .where(name: name)
          .where.not(repository_id: nil)
          .distinct
          .includes(:repository)
          .map(&:repository)
    else
      @repositories2 = []
    end

    @repositories3 =
      if (category_option = CategoryOption.find_by(name: name))
        Category
          .where(category_option_id: category_option.id)
          .distinct
          .includes(:repository)
          .map(&:repository)
      else
        []
      end

    @repositories =
      (@repositories1 + @repositories2 + @repositories3)
        .uniq
        .sort_by { |s| -s[sort_arr.first].to_i }
        .paginate(per_page: 12, page: params[:page])

    if params["featured"]
      @repositories =
        (@repositories1 + @repositories2 + @repositories3)
          .uniq
          .select(&:featured?)
          .uniq
          .sort_by(&:updated_at)
          .reverse
          .paginate(per_page: 12, page: params[:page])
    end

    @photos = photo_hash
  end

  def equipment
    sort_arr = sort_order

    name = params[:slug].gsub("-", " ")
    @repositories =
      Equipment
        .where(name: name)
        .distinct
        .includes(:repository)
        .map(&:repository)
        .paginate(per_page: 12, page: params[:page]) do
          order_by sort_arr.first, sort_arr.last
        end

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
    photos = Photo.find(photo_ids.values)
    photos.inject({}) { |h, e| h.merge!(e.repository_id => e) }
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

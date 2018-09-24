class SearchController < SessionsController
  before_action :current_user

  def explore
    @repositories = Repository.paginate(:per_page=>12,:page=>params[:page]).public_repos.order([sort_order].to_h).page params[:page]
    @photos = photo_hash
  end

  def search
  	sort_arr = sort_order
  	@repositories = Repository.paginate(:per_page=>12,:page=>params[:page]).public_repos.order([sort_arr].to_h).where("lower(title) LIKE ?
                                                OR lower(description) LIKE ?
                                                OR lower(user_username) LIKE ?
                                                OR lower(category) LIKE ?",
                                  "%#{params[:q].downcase}%",
                                  "%#{params[:q].downcase}%",
                                  "%#{params[:q].downcase}%",
                                  "%#{params[:q].downcase}%").distinct
    @photos = photo_hash
  end

  def category
    sort_arr = sort_order

    if category = SLUG_TO_OLD_CATEGORY[params[:slug]]
      @repositories1 = Repository.where(category: category).distinct
    else
      @repositories1 = []
    end

    if name = SLUG_TO_CATEGORY_MODEL[params[:slug]]
      @repositories2 = Category.where(name: name).where.not(repository_id: nil).distinct.includes(:repository).map(&:repository)
    else
      @repositories2 = []
    end

    if categroy_option = CategoryOption.find_by(name: name)
      @repositories3 = Category.where(category_option_id: categroy_option.id).distinct.includes(:repository).map(&:repository)
    else
      @repositories3 = []
    end

    @repositories = (@repositories1 + @repositories2 + @repositories3).uniq.sort_by { |s| -s[sort_arr.first].to_i}.paginate(:per_page=>12,:page=>params[:page])

    if params['featured']
      @repositories = (@repositories1 + @repositories2 + @repositories3).uniq.select{|r| r.featured?}.uniq.sort_by(&:updated_at).reverse.paginate(:per_page=>12,:page=>params[:page])
    end

    @photos = photo_hash

  end

  def equipment
    sort_arr = sort_order

    name = params[:slug].gsub('-', ' ')
    @repositories =  Equipment.where(name: name).distinct.includes(:repository).map(&:repository).paginate(:per_page=>12,:page=>params[:page]) do
      order_by sort_arr.first, sort_arr.last
    end

    @photos = photo_hash
  end


	private

	def sort_order
		case params[:sort]
    	when 'newest' then [:created_at, :desc]
    	when 'most_likes' then [:like, :desc]
    	when 'most_makes' then [:make, :desc]
    	when 'recently_updated' then [:updated_at, :desc]
    	else [:created_at, :desc]
    end
	end

  def photo_hash
    repository_ids = @repositories.map(&:id)
    photo_ids = Photo.where(repository_id: repository_ids).group(:repository_id).minimum(:id)
    photos = Photo.find(photo_ids.values)
    photos.inject({}) { |h,e| h.merge!(e.repository_id => e) }
  end

  SLUG_TO_OLD_CATEGORY = {
    'internet-of-things' => 'Internet of Things',
    'virtual-reality' => 'Virtual Reality',
    'health-sciences' => 'Bio-Medical',
    'mobile-development' => 'mobile',
    'other-projects' => '3D-Model',
    'wearable' => 'Wearables'
  }

  SLUG_TO_CATEGORY_MODEL = {
   'internet-of-things' => 'Internet of Things',
   'course-related-projects' => 'Course-related Projects',
   'gng2101/gng2501' => 'GNG2101/GNG2501',
   'gng1103/gng1503' => 'GNG1103/GNG1503',
   'health-sciences' => 'Health Sciences',
   'wearable' => 'Wearable',
   'mobile-development' => 'Mobile Development',
   'virtual-reality' => 'Virtual Reality',
   'other-projects' => 'Other Projects',
   'uottawa-team-projects' => "uOttawa Team Projects",
  }

end

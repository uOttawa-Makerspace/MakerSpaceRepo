class SearchController < SessionsController
  before_action :current_user
  # before_action :signed_in
  require 'will_paginate/array'

  def explore
    @repositories = Repository.order([sort_order].to_h).page params[:page]
    @photos = photo_hash
  end

  def search
  	sort_arr = sort_order
  	@repositories = Repository.paginate(:per_page=>1,:page=>params[:page]).where("lower(title) LIKE ?
                                                OR lower(description) LIKE ?
                                                OR lower(user_username) LIKE ?
                                                OR lower(category) LIKE ?",
                                  "%#{params[:q].downcase}%",
                                  "%#{params[:q].downcase}%",
                                  "%#{params[:q].downcase}%",
                                  "%#{params[:q].downcase}%").uniq
    @photos = photo_hash
  end

  def category
    sort_arr = sort_order
    @repositories = []
    if category = SLUG_TO_OLD_CATEGORY[params[:slug]]
      @repositories += Repository.where(category: category)
    end
    if name = SLUG_TO_CATEGORY_MODEL[params[:slug]]
      @repositories += Category.where(name: name).includes(:repository).map(&:repository)
    end
    @repositories = @repositories.uniq
    @repositories.paginate(:per_page=>12,:page=>params[:page]) do
      order_by sort_arr.first, sort_arr.last
    end
    @photos = photo_hash
  end

  def equipment
    sort_arr = sort_order
    @repositories = Repository.where("equipment LIKE ?", "%#{params[:slug]}%").paginate(:per_page=>12,:page=>params[:page]) do
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
   'health-sciences' => 'Health Sciences',
   'wearable' => 'Wearable',
   'mobile-development' => 'Mobile Development',
   'virtual-reality' => 'Virtual Reality',
   'other-projects' => 'Other Projects',
   'uottawa-team-projects' => "uOttawa Team Projects"
  }

end

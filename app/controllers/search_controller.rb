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
  	@repositories = Repository.where("title LIKE ?
                                  OR description LIKE ?
                                  OR user_username LIKE ?
                                  OR category LIKE ?",
                                  "%#{params[:q]}%", "%#{params[:q]}%", "%#{params[:q]}%", "%#{params[:q]}%").paginate(:per_page=>12,:page=>params[:page]) do
	    order_by sort_arr.first, sort_arr.last
	  end

    @photos = photo_hash
  end

  def category
    sort_arr = sort_order
    repositories_by_category = Repository.where("category LIKE ?", "%#{params[:slug]}%")
    repositories_by_categories = []
    Category.where('lower(name) LIKE ?', params[:slug].downcase).each do |cat|
      repositories_by_categories << cat.repository
    end
    @repositories = repositories_by_category + repositories_by_categories
    @repositories.uniq
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

end

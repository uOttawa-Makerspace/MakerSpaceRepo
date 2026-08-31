# frozen_string_literal: true

class MakesController < SessionsController
  before_action :current_user
  before_action :signed_in
  before_action :set_repository

  # A make is just another repository that points to another one
  def create
    @make =
      @repository.makes.build do |r|
        r.title = make_params[:title]
        r.description = make_params[:description]
        r.license = @repository.license
        r.github = @repository.github
        r.github_url = @repository.github_url
        r.user_id = @user.id
        r.share_type = 'public'
        r.photos_attributes = make_params[:photos_attributes]
        r.slug =
          "#{r.id}.#{r.title.downcase.gsub(/[^0-9a-z ]/i, '').gsub(/\s+/, '-')}"
      end

    if @make.save
      copy_categories_and_equipment
      @repository.increment!(:make)
      redirect_to repository_path(@user.username, @make.slug)
      @user.increment!(:reputation, 15)
    else
      flash[:alert] = 'Something went wrong'
      @repo = @repository
      render :new
    end
  end

  def new
    @make = @repository
    @repo = @repository
  end

  private

  def make_params
    params.require(@repository.title).permit(
      :title,
      :description,
      photos_attributes: %i[id image _destroy]
    )
  end

  def set_repository
    @repository =
      Repository.includes(:owner).find_by(
        owner: {
          username: params[:user_username]
        },
        id: params[:id]
      )
  end

  def create_photos
    if params[:images].present?
      params[:images].each do |img|
        dimension = FastImage.size(img.tempfile, raise_on_failure: true)
        Photo.create(
          image: img,
          repository_id: @make.id,
          width: dimension.first,
          height: dimension.last
        )
      end
    end
  end

  def copy_categories_and_equipment
    @repository.categories.each do |c|
      Category.create(
        name: c.name,
        repository_id: @make.id,
        category_option_id: c.category_option_id
      )
    end
    @repository.equipments.each do |e|
      Equipment.create(name: e.name, repository_id: @make.id)
    end
  end
end

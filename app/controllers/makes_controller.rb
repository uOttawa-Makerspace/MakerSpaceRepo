# frozen_string_literal: true

class MakesController < SessionsController
  before_action :current_user
  before_action :signed_in
  before_action :set_repository

  def create
    @repo = @repository.makes.build do |r|
      r.title = params[@repository.title][:title]
      r.description = params[@repository.title][:description]
      r.license = @repository.license
      r.github = @repository.github
      r.github_url = @repository.github_url
      r.user_username = @user.username
      r.user_id = @user.id
      r.share_type = "public"
    end

    if @repo.save
      begin
        create_photos
      rescue FastImage::ImageFetchFailure, FastImage::UnknownImageType, FastImage::SizeNotFound => e  
        flash[:alert] = 'Something went wrong while uploading photos, but the make was created. Try uploading them again later.'
        @repo.destroy
        render json: {redirect_uri: request.path}
      else
        @repo.update(slug: @repo.id.to_s + '.' + @repo.title.downcase.gsub(/[^0-9a-z ]/i, '').gsub(/\s+/, '-'))
        copy_categories_and_equipment
        @repository.increment!(:make)
        render json: { redirect_uri: repository_path(@user.username, @repo.slug).to_s }
        @user.increment!(:reputation, 15)
      end
    else
      flash[:alert] = 'Something went wrong'
      render json: @repo.errors['title'].first, status: :unprocessable_entity
    end
  end

  def new
    @repo = @repository.title
  end

  private

  def set_repository
    @repository = Repository.find_by(user_username: params[:user_username], id: params[:id])
  end

  def create_photos
    if params[:images].present?
      params[:images].each do |img|
        dimension = FastImage.size(img.tempfile,raise_on_failure: true)
        Photo.create(image: img, repository_id: @repo.id, width: dimension.first, height: dimension.last)
      end
      end
  end

  def copy_categories_and_equipment
    @repository.categories.each do |c|
      Category.create(name: c.name, repository_id: @repo.id, category_option_id: c.category_option_id)
    end
    @repository.equipments.each do |e|
      Equipment.create(name: e.name, repository_id: @repo.id)
    end
  end
end

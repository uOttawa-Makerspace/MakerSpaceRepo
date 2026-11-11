# frozen_string_literal: true

class MakesController < SessionsController
  before_action :current_user
  before_action :signed_in
  before_action :set_repository
  before_action -> { ensure_repository_unlocked(@repository) }

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
        r.users << @user
        r.share_type = 'public'
        r.photos_attributes = photo_attributes
        r.slug =
          "#{r.id}.#{r.title.downcase.gsub(/[^0-9a-z ]/i, '').gsub(/\s+/, '-')}"
      end

    if @make.save
      copy_categories_and_equipment
      @repository.increment!(:make)
      redirect_to repository_path(@user.username, @make.slug)
      @user.increment!(:reputation, 15)
    else
      flash.now[:alert] = validation_message(@make, 'errors.makes.not_created')
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
    params.require(:repository).permit(
      :title,
      :description,
      photos_attributes: %i[id image _destroy]
    )
  end

  def set_repository
    @repository =
      Repository.includes(:owner).find_by!(
        owner: {
          username: params[:user_username]
        },
        id: params[:id]
      )
  end

  # The files the make form posts as images[] (each becomes a Photo checked by
  # its validations); photos_attributes is accepted too. Without either, the
  # make fails the photo count validation.
  def photo_attributes
    uploads = Array(params[:images]).grep(ActionDispatch::Http::UploadedFile)
    return uploads.map { |image| { image: image } } if uploads.any?

    make_params[:photos_attributes] || []
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

class Staff::MakerstoreLinksController < StaffAreaController
  def index
    @makerstore_links = MakerstoreLink.all
  end

  def show
    @makerstore_link = MakerstoreLink.find(params[:id])
  end

  def new
    @makerstore_link = MakerstoreLink.new
  end

  def create
    @makerstore_link = MakerstoreLink.new(makerstore_link_params)
    unless makerstore_link_params[:image]
      render :new,
             status: :unprocessable_entity,
             alert: "Cannot create makerstore link without an image"
      return
    end
    # file is uploaded to temporary storage
    temp_filepath = makerstore_link_params[:image].tempfile.path
    # compress the temporary file before upload
    resized =
      ImageProcessing::MiniMagick.source(temp_filepath).resize_to_fit!(220, 250)
    # Reattach new temp file
    @makerstore_link.image.attach(
      io: resized,
      filename: makerstore_link_params[:image].original_filename
    )
    if @makerstore_link.save
      flash[:notice] = "Link created"
      redirect_to staff_makerstore_links_path
    else
      flash[:alert] = "Link not created: " +
        @makerstore_link.errors.full_messages.join(", ")
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @makerstore_link = MakerstoreLink.find(params[:id])
    render :new
  end

  def reorder
    if params[:data].present?
      ordered_link =
        (params[:data].map(&:to_i) + MakerstoreLink.all.pluck(:id)).uniq
      ordered_link.each_with_index do |id, index|
        MakerstoreLink.find(id).update(order: index)
      end
    end
    respond_to do |format|
      format.json { render json: MakerstoreLink.all.pluck(:id, :order) }
    end
  end

  def update
    @makerstore_link = MakerstoreLink.find(params[:id])
    if @makerstore_link.update(makerstore_link_params)
      flash[:notice] = "Link updated"
      redirect_to staff_makerstore_links_path
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @makerstore_link = MakerstoreLink.find(params[:id])
    if @makerstore_link.destroy
      flash[:notice] = "Link destroyed"
    else
      flash[:alert] = "Error destroying link: " +
        @makerstore_link.errors.full_messages.join(", ")
    end
    redirect_to staff_makerstore_links_path, status: :see_other
  end

  private

  def makerstore_link_params
    params.require(:makerstore_link).permit(
      :title,
      :url,
      :image,
      :shown,
      :order
    )
  end
end

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
    params.require(:makerstore_link).permit(:title, :url, :image, :order)
  end
end

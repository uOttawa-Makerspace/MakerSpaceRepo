# frozen_string_literal: true

class FaqsController < SessionsController
  before_action :no_container, only: :index
  before_action :ensure_admin, except: :index

  def index
    @faqs = Faq.all
  end

  def new
    @faq = Faq.new
  end

  def create
    @faq = Faq.new(faq_params)
    if @faq.save
      flash[:notice] = "Created FAQ successfully"
      # make way for new faq
      @faq = Faq.new
      render :new
    else
      flash[:alert] = "Created FAQ successfully"
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @faq = Faq.find(params[:id])
  end

  def update
    @faq = Faq.find(params[:id])
    if @faq.update(faq_params)
      flash[:notice] = "Done"
      redirect_to faqs_path
    else
      flash[:alert] = "Failed to update entry"
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if Faq.find(params[:id]).destroy
      flash[:notice] = "Entry deleted"
      redirect_to faqs_path
    end
  end

  def reorder
    # Ensure we only receive cold hard integers
    # Because we're essentially trusting the client
    # Anything that's missing, we ignore
    # spooky scary internet
    # Create full order list
    # New entries don't have an order yet
    if params[:data].present?
      ordered_faq = (params[:data].map(&:to_i) + Faq.all.pluck(:id)).uniq
      ordered_faq.each_with_index do |id, index|
        Faq.find(id).update(order: index)
      end
    end
    respond_to { |format| format.json { render json: "ping" } }
  end

  private

  # reorder doesn't use this
  def faq_params
    params.require(:faq).permit(
      :title_en,
      :title_fr,
      :body_en,
      :body_fr,
      :order
    )
  end

  def ensure_admin
    redirect_to "/" and return unless current_user.admin?
  end
end

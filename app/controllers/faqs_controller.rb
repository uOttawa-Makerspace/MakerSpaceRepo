# frozen_string_literal: true

class FaqsController < ApplicationController
  layout "application"
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

  private

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

class QuickAccessLinksController < ApplicationController
  before_action :check_user

  def check_user
    if current_user.nil?
      redirect_to root_path, notice: "You must be logged in to do that"
    end
    if params[:id].present?
      if QuickAccessLink.find(params[:id]).user_id != current_user.id
        redirect_to root_path, notice: "You can't do that"
      end
    end
  end

  def create
    QuickAccessLink.create(
      user_id: current_user.id,
      name: params[:name],
      path: params[:path]
    )
    redirect_to user_path(current_user.username),
                notice: "Quick access link created"
  end

  def update
    if params[:name].blank? || params[:path].blank?
      QuickAccessLink.find(params[:id]).destroy
      redirect_to user_path(current_user.username)
      return
    end
    QuickAccessLink.find(params[:id]).update(
      name: params[:name],
      path: params[:path]
    )
    redirect_to user_path(current_user.username), notice: "Link updated"
  end

  def delete
    QuickAccessLink.find(params[:id]).destroy
    redirect_to user_path(current_user.username), notice: "Link deleted"
  end
end

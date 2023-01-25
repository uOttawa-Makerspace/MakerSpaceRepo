class QuickAccessLinksController < ApplicationController
  def create
    QuickAccessLink.create(
      user_id: current_user.id,
      name: params[:name],
      path: params[:path]
    )
    redirect_to user_path(current_user.username)
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
    redirect_to user_path(current_user.username)
  end
end

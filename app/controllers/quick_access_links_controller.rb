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
    qal =
      QuickAccessLink.new(
        user_id: current_user.id,
        name: params[:name],
        path: params[:path]
      )
    if qal.save
      redirect_back fallback_location: root_path,
                    notice: "Quick access link created"
    else
      redirect_back fallback_location: root_path,
                    notice:
                      "Quick access link not created, #{qal.errors.full_messages.join(", ")}"
    end
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
    redirect_back fallback_location: root_path, notice: "Link deleted"
  end
end

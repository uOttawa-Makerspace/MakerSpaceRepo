class QuickAccessLinksController < SessionsController
  before_action :check_user

  # Only admins, and only on their own links. Every refusal is one redirect.
  def check_user
    return if current_user.admin? && own_link_or_none?

    redirect_to root_path, notice: "You can't do that"
  end

  def own_link_or_none?
    params[:id].blank? || QuickAccessLink.find(params[:id]).user_id == current_user.id
  end

  def create
    qal =
      QuickAccessLink.new(
        user_id: current_user.id,
        name: params[:name],
        path: params[:path]
      )
    if qal.save
      # no response to trigger default reload
      # redirect_back fallback_location: root_path
    else
      redirect_back fallback_location: root_path,
                    alert:
                      validation_message(qal, "failed_saves.quick_access_link")
    end
  end

  def update
    if params[:name].blank? || params[:path].blank?
      QuickAccessLink.find(params[:id]).destroy
      redirect_to user_path(current_user.username)
      return
    end
    quick_link = QuickAccessLink.find(params[:id])
    if quick_link.update(name: params[:name], path: params[:path])
      #redirect_back fallback_location: user_path(current_user.username), notice: "Link updated"
    else
      redirect_back fallback_location: user_path(current_user.username), alert: "Link not valid"
    end
  end

  def delete
    QuickAccessLink.find(params[:id]).destroy
    # For delete we want to redirect, because for some reason turbo does not reload on delete methods
    # Might be something application side that disables that for some reason, but I haven't been able to find it.
    redirect_back fallback_location: root_path
  end
end

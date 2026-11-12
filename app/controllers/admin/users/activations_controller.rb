# frozen_string_literal: true

# Reactivating (create) and deactivating (destroy) an account. Nothing the user made or did is deleted;
# deactivation ends every credential issued so far (User#deactivate!).
class Admin::Users::ActivationsController < AdminAreaController
  before_action :load_user

  def create
    @target.reactivate!
    redirect_to admin_user_path(@target), notice: t("admin.users.activation.reactivated")
  end

  def destroy
    unless @target.deactivatable_by?(current_user)
      return redirect_to admin_user_path(@target), alert: t("admin.users.activation.self_refused")
    end

    @target.deactivate!
    redirect_to admin_user_path(@target), notice: t("admin.users.activation.deactivated")
  rescue User::LastAdminError => e
    redirect_to admin_user_path(@target), alert: e.message
  end

  private

  def load_user
    @target = User.find(params[:user_id])
  end
end

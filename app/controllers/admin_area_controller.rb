# frozen_string_literal: true

class AdminAreaController < SessionsController
  before_action :current_user
  before_action :ensure_admin

  private

  # A guest is sent to sign in (and back here afterwards); a signed-in user who
  # is not an admin goes to the home page.
  def ensure_admin
    return signed_in unless signed_in?

    @user = current_user
    redirect_to "/" and return unless @user.admin?
  end
end

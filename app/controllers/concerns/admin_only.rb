# frozen_string_literal: true

# The admin-only gate. A guest is sent to sign in (and back afterwards; a
# script or JSON request gets 401 instead); a signed-in user who is not an
# admin goes to the home page. Controllers add `before_action :ensure_admin`
# with whatever `only:`/`except:` they need.
module AdminOnly
  private

  def ensure_admin
    return signed_in unless signed_in?

    @user = current_user
    redirect_to "/" and return unless @user.admin?
  end
end

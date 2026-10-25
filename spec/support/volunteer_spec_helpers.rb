# frozen_string_literal: true

# Shared helpers for the Volunteers characterization specs (chunk 13).
#
# Authentication is the custom session; request specs sign in through the real
# login POST (the `sign_in_via_session` shim does not work in type: :request).
#
# `volunteer?` is derived from a Program row of type Program::VOLUNTEER, NOT
# from `users.role`; `role: "volunteer"` alone grants nothing. The roles below
# are therefore built explicitly:
#   :guest      nobody signed in (`current_user` is an unsaved User.new)
#   :regular    regular_user, no program
#   :role_only  role "volunteer" but NO Volunteer Program row
#   :volunteer  role volunteer + active Volunteer Program
#   :inactive   role volunteer + Volunteer Program with active: false
#   :staff, :admin
module VolunteerSpecHelpers
  VOLUNTEER_PASSWORD = "asa32A353#"

  def vol_login!(user)
    post login_authentication_path,
         params: { username_email: user.username, password: VOLUNTEER_PASSWORD }
    expect(response).to redirect_to(root_path)
    user
  end

  def build_vol_user(role)
    case role
    when :guest then nil
    when :regular then create(:user, :regular_user)
    when :role_only then create(:user, :volunteer)
    when :volunteer then create(:user, :volunteer_with_volunteer_program)
    when :inactive then create(:user, :unactive_volunteer_with_volunteer_program)
    when :staff then create(:user, :staff)
    when :admin then create(:user, :admin)
    else raise ArgumentError, role.inspect
    end
  end

  # Signs in as +role+ (nobody for :guest) and returns the user (or nil).
  def vol_sign_in_as(role)
    user = build_vol_user(role)
    vol_login!(user) if user
    user
  end

  def vol_deliveries
    ActionMailer::Base.deliveries
  end

  def vol_error_text
    CGI.unescapeHTML(response.body)
  end
end

RSpec.configure { |config| config.include VolunteerSpecHelpers, type: :request }

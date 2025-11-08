# frozen_string_literal: true

module ApplicationHelper
  attr_accessor :github

  def sign_in(username_email, password)
    user = User.authenticate(username_email, password)
    session[:user_id] = user.id unless user.nil?
    user
  end

  def sign_out
    session[:user_id] = nil
    session[:authorized_repo_ids] = nil
    session[:selected_dates] = nil
  end

  def current_user
    @user ||= User.find(session[:user_id]) if signed_in?
    @user ||= User.new
  end

  def github_client
    @github_client ||=
      Octokit::Client.new(access_token: @user.access_token) if github?
  end

  def signed_in?
    session[:user_id].present? || has_valid_jwt?
  end

  def has_valid_jwt?
    auth_header = request.headers["Authorization"]
    if auth_header
      user_token = auth_header.split(" ")[1]
      begin
        decoded_token =
          JWT.decode(
            user_token,
            Rails.application.credentials.secret_key_base,
            true,
            { algorithm: "HS256" }
          )
        session[:user_id] = decoded_token[0]["user_id"]
        return true
      rescue JWT::ExpiredSignature
        return false
      rescue JWT::DecodeError
        return false
      end
    end

    false
  end

  def github?
    current_user.access_token.present?
  end

  def locales_change
    locales = I18n.available_locales.clone
    locales.delete(I18n.locale)
    locales
  end

  def license_url
    {
      "Creative Commons - Attribution" => licenses_cca_path,
      "Creative Commons - Attribution - Share Alike" => licenses_ccasa_path,
      "Creative Commons - Attribution - No Derivatives" => licenses_ccand_path,
      "Creative Commons - Attribution - Non-Commercial" => licenses_ccanc_path,
      "Attribution - Non-Commercial - Share Alike" => licenses_ancsa_path,
      "Attribution - Non-Commercial - No Derivatives" => licenses_ancnd_path
    }
  end

  private

  def page_title(curr_page = "", base_title: "MakerRepo")
    #base_title = "MakerRepo"
    curr_page.empty? ? base_title : curr_page + " | " + base_title
  end

  def youtube_video(url)
    render partial: "partials/streaming", locals: { url: url }
  end

  def load_rakes
    require "rake"
    MakerSpaceRepo::Application.load_tasks if Rake::Task.tasks.empty?
  end

  def end_of_this_semester
    if DateTime.now.month in 9..12
      # End of Fall
      DateTime.new(DateTime.now.year, 12).end_of_month
    elsif DateTime.now.month in 1..4
      # End of Winter
      DateTime.new(DateTime.now.year, 4).end_of_month
    elsif DateTime.now.month in 5..8
      # End of Summer
      DateTime.new(DateTime.now.year, 8).end_of_month
    end
  end

  def no_container
    @no_container = true
  end

  def with_development_header
    @with_development_header = true
  end

  def with_volunteer_header
    @with_volunteer_header = true
  end

  def with_admin_header
    @with_admin_header = true
  end

  def with_staff_header
    @with_staff_header = true
  end
end

def rgba(color, opacity)
  "rgba(#{color.join(", ")}, #{opacity})"
end

# frozen_string_literal: true

require Rails.root.join("lib/jwt_authenticator")

module ApplicationHelper
  # Keys that are not about who is signed in and must survive the session
  # reset done on sign-in (sign-out keeps only the locale).
  SESSION_KEYS_KEPT_ON_SIGN_IN = %w[locale authorized_repo_ids selected_dates order_id].freeze

  # Every login path (HTML, JSON, SAML) goes through here, so the refusals live
  # here: a lock still in effect (checked BEFORE the password so a locked account
  # cannot be probed or have its lock rewritten by failed attempts), a
  # deactivated account (D-I03) and an unconfirmed one. The caller words the
  # refusal from @sign_in_refusal (:locked, :inactive, :unconfirmed).
  def sign_in(username_email, password)
    result = CredentialAuthenticator.call(username_email, password)
    @sign_in_refusal = result.refusal
    user = result.user
    unless user.nil?
      kept = session.to_hash.slice(*SESSION_KEYS_KEPT_ON_SIGN_IN)
      reset_session # new session id on privilege change (session fixation)
      kept.each { |key, value| session[key] = value }
      session[:user_id] = user.id
      session[:token_version] = user.token_version
      SessionAuthenticator.touch(session) # a new session gets a full idle window
      reset_auth_memo # a user memoized earlier in this request (set_last_seen_at) is stale now
    end
    user
  end

  # " or wait 5 minutes" for a timed (brute-force) lockout (see CredentialAuthenticator).
  def lock_wait_suffix(user, verb = "wait")
    CredentialAuthenticator.lock_wait_suffix(user, verb)
  end

  def sign_out
    locale = session[:locale]
    reset_session
    session[:locale] = locale if locale
    reset_auth_memo
  end

  def current_user
    @user ||= session_user
    @user ||= jwt_user
    @user ||= User.new
  end

  # The cookie-session user, or nil. A session that is idle-expired (72h), whose
  # stored token_version no longer matches the user's (password changed/reset
  # elsewhere; a session without the key is version 0), or whose user was
  # deactivated (D-I03) is ended (SessionAuthenticator.valid_for?).
  def session_user
    return @session_user if defined?(@session_user)

    @session_user = nil
    return nil if session[:user_id].blank?

    user = User.find_by(id: session[:user_id])
    if SessionAuthenticator.valid_for?(session, user)
      @session_user = user
    else
      sign_out
    end
    @session_user
  end

  def signed_in?
    session_user.present? || has_valid_jwt?
  end

  def has_valid_jwt?
    jwt_user.present?
  end

  # The user a valid Bearer token authenticates. Not written to the session:
  # a Bearer request must not mint a cookie session.
  def jwt_user
    return @jwt_user if defined?(@jwt_user)

    @jwt_user = JwtAuthenticator.user_for(request.headers["Authorization"])
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

  # Forget who was resolved earlier in this request (cookie user, current user,
  # Bearer user) so the next call looks again. Used when the session changes.
  def reset_auth_memo
    %i[@session_user @user @jwt_user].each do |ivar|
      remove_instance_variable(ivar) if instance_variable_defined?(ivar)
    end
  end

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
end

def rgba(color, opacity)
  "rgba(#{color.join(", ")}, #{opacity})"
end

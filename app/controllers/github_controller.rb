# frozen_string_literal: true

class GithubController < SessionsController
  before_action :current_user
  before_action :signed_in, except: [:callback]
  before_action :github_client, only: [:repositories]

  CLIENT_ID = ENV['GITHUB_APP_KEY']
  CLIENT_SECRET = ENV['GITHUB_APP_KEY_SECRET']

  def authorize
    address = github.authorize_url CLIENT_ID, scope: 'repo'
    redirect_to address
  end

  def unauthorize
    github.revoke_application_authorization(@user.access_token)
    @user.update access_token: nil
    flash[:notice] = 'Successfully revoked access to github account.'
    redirect_to settings_admin_path
  end

  def callback
    user = User.find(session[:user_id])
    access_token = Octokit.exchange_code_for_token(params[:code], CLIENT_ID, CLIENT_SECRET).access_token
    user.update access_token: access_token
    redirect_to settings_admin_path
  end

  def repositories
    @repos = @github_client.repos.inject([]) { |a, e| a.push(e.name) }
  end

  private

  def github
    @github ||= Octokit::Client.new
  end
end

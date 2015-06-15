class GithubController < SessionsController
  before_action :current_user
  before_action :signed_in, except: [:callback]

  CLIENT_ID = ENV['GITHUB_APP_KEY']
  CLIENT_SECRET = ENV['GITHUB_APP_KEY_SECRET']

  def authorize
    session[:back] = request.referrer
    address = github.authorize_url CLIENT_ID, scope: 'repo'
    redirect_to address
  end

  def repositories
    @repos = octokit_client.repos.list.map { |r| r.name unless r.private}.compact
  end

  def unauthorize
    github.revoke_application_authorization(@user.access_token)
    @user.update access_token: nil
    redirect_to account_setting_user_path(@user) 
  end

  def callback
    code = params[:code]
    access_token = Octokit.exchange_code_for_token(code, CLIENT_ID, CLIENT_SECRET).access_token
    @user.update access_token: access_token
    redirect_to root_path
    session.delete :back
  end

  private

   def github
    @github ||= Octokit::Client.new
   end

end

class GithubController < SessionsController
  before_action :current_user
  before_action :signed_in

  def authorize
    session[:back] = request.referrer
    address = github.authorize_url redirect_uri: "http://localhost:3000/github/callback", scope: 'repo'
    redirect_to address
  end

  def repositories
    @repos = github_client.repos.list.map { |r| r.name unless r.private}.compact
  end

  def unauthorize
  end

  def callback
    authorization_code = params[:code]
    access_token = github.get_token authorization_code
    @user.access_token = access_token.token
    @user.save
    redirect_to session[:back]
    session.delete :back
  end

  private

   def github
    @github ||= Github.new
   end

end

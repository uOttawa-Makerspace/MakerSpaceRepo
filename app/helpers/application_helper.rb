module ApplicationHelper

  attr_accessor :github

  def current_user
    @user = User.find(session[:user_id]) if signed_in?
    @user ||= User.new
  end

  def github_client
    @github_client ||= Octokit::Client.new(access_token: @user.access_token) if github?
  end

  def signed_in?
    session[:user_id].present?
  end

  def github?
    current_user.access_token.present?
  end

  # def file_system(path="/", full=false)
  #   github_client
  #   root = @github.metadata(path)["contents"]
  #   full ? file_system_stucture(root) : relative_file_system(root)
  # end

  private

  # def file_system_stucture(array)
  #   return {} if array.empty?
  #   array.inject({}) do |h, e|
  #     name = e["path"].scan(/[^\/]+$/).first
  #     if e["is_dir"]
  #       h[name] = file_system_stucture(@github.metadata(e["path"])["contents"])
  #     else
  #       h[name] = "file"
  #     end
  #     h
  #   end
  # end

  # def relative_file_system(root)
  #   root.inject([]) do |a, e|
  #     file_or_dir = e["is_dir"] ? "directory" : "file"
  #     a << { e["path"].scan(/[^\/]+$/).first => file_or_dir }
  #   end
  # end

  # def all_directories(array, a=[])
  #   array.inject(a) do |a, e|
  #     if e["is_dir"]
  #       a << e["path"].scan(/[^\/]+$/).first
  #       all_directories(@github.metadata(e["path"])["contents"], a)
  #     end
  #     a
  #   end
  # end

end


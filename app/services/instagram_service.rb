class InstagramService
    require 'net/http'
    require 'json'
  
    INSTAGRAM_API_URL = "https://graph.instagram.com/me/media?fields=id,caption,media_type,media_url,permalink&access_token="
  
    def initialize(access_token)
      @access_token = access_token
    end
  
    def fetch_posts
      uri = URI("#{INSTAGRAM_API_URL}#{@access_token}")
      response = Net::HTTP.get(uri)
      JSON.parse(response)
    rescue => e
      Rails.logger.error("Failed to fetch Instagram posts: #{e.message}")
      []
    end
  end
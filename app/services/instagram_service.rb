# frozen_string_literal: true

class InstagramService
  INSTAGRAM_API_URL =
    "https://graph.instagram.com/me/media?fields=media_type,media_url,permalink,thumbnail_url&access_token="

  def self.fetch_posts
    access_token =
      Rails.application.credentials[Rails.env.to_sym][:instagram][:access_token]
    response = Excon.get("#{INSTAGRAM_API_URL}#{access_token}")
    parsed_response = JSON.parse(response.body)
    parsed_response || {}
  rescue StandardError
    {}
  end
end

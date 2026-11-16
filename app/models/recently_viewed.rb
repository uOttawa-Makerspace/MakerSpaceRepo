# frozen_string_literal: true

# The links in the unsigned recently_viewed cookie (a JSON object of link to title). The cookie can be
# edited by its owner, so only entries whose link is a path on this site are kept.
class RecentlyViewed
  LOCAL_PATH = %r{\A/(?![/\\])[^\s\x00-\x1f]*\z}

  def self.parse(raw)
    parsed = JSON.parse(raw.to_s)
    return {} unless parsed.is_a?(Hash)

    parsed.select { |link, title| local_path?(link) && title.is_a?(String) }
  rescue JSON::ParserError
    {}
  end

  def self.local_path?(link)
    link.match?(LOCAL_PATH)
  end
end

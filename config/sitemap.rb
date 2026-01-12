# frozen_string_literal: true

SitemapGenerator::Sitemap.default_host = "https://makerepo.com"

SitemapGenerator::Sitemap.create do
  # ============================================
  # STATIC PAGES
  # ============================================
  # Note: Root path "/" is added automatically by the gem with default settings
  # Only add it once if you want custom settings:
  add "/", changefreq: "daily", priority: 1.0

  add "/about", changefreq: "monthly", priority: 0.8
  add "/contact", changefreq: "monthly", priority: 0.7
  add "/hours", changefreq: "weekly", priority: 0.7
  add "/open_hours", changefreq: "weekly", priority: 0.6
  add "/terms_of_service", changefreq: "yearly", priority: 0.3
  add "/calendar", changefreq: "daily", priority: 0.6
  add "/get_involved", changefreq: "monthly", priority: 0.7
  add "/resources", changefreq: "monthly", priority: 0.7
  add "/labs", changefreq: "monthly", priority: 0.7
  add "/faq", changefreq: "weekly", priority: 0.6
  add "/help", changefreq: "monthly", priority: 0.5

  # NOTE: /explore is excluded - blocked in robots.txt due to heavy images
  # NOTE: /search is excluded - blocked in robots.txt

  # ============================================
  # LICENSE PAGES
  # ============================================
  %w[
    common_creative_attribution
    common_creative_attribution_share_alike
    common_creative_attribution_no_derivatives
    common_creative_attribution_non_commercial
    attribution_non_commercial_share_alike
    attribution_non_commercial_no_derivatives
  ].each do |license|
    add "/licenses/#{license}", changefreq: "yearly", priority: 0.3
  end

  # ============================================
  # GETTING STARTED GUIDES
  # ============================================
  add "/getting-started/setting-up-account", changefreq: "monthly", priority: 0.6
  add "/getting-started/creating-repository", changefreq: "monthly", priority: 0.6

  # ============================================
  # DYNAMIC CONTENT - Uncomment as needed
  # ============================================

  # # Public User Profiles
  # User.where(public_profile: true).find_each do |user|
  #   add "/#{user.username}",
  #       lastmod: user.updated_at,
  #       changefreq: "weekly",
  #       priority: 0.5
  # end

  # # Public Repositories
  # Repository.publicly_visible.find_each do |repo|
  #   add "/#{repo.user.username}/#{repo.id}",
  #       lastmod: repo.updated_at,
  #       changefreq: "weekly",
  #       priority: 0.6
  # end
end
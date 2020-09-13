module LearningAreaHelper
  def valid_url?(url)
    clean_url = strip_tags(url)
    url_regexp = /^(http|https):\/\/[a-z0-9]+([\-\.]{1}[a-z0-9]+)*\.[a-z]{2,5}(:[0-9]{1,5})?(\/.*)?$/ix
    clean_url =~ url_regexp and clean_url.include?("wiki.makerepo.com") ? true : false
  end
end

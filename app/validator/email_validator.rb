class EmailValidator < ActiveModel::EachValidator
  def levenshtein_distance(a, b)
    # https://medium.com/@ethannam/understanding-the-levenshtein-distance-equation-for-beginners-c4285a5604f0
    a_magnitude = a.length
    b_magnitude = b.length
    return b_magnitude if a_magnitude == 0
    return a_magnitude if b_magnitude == 0

    distance_matrix = Array.new(a_magnitude + 1) { Array.new(b_magnitude + 1) }
    (0..a_magnitude).each { |i| distance_matrix[i][0] = i }
    (0..b_magnitude).each { |j| distance_matrix[0][j] = j }

    (1..b_magnitude).each do |b_index|
      (1..a_magnitude).each do |a_index|
        distance_matrix[a_index][b_index] = if a[a_index - 1] == b[b_index - 1]
          # adjust index into string
          distance_matrix[a_index - 1][b_index - 1] # no operation required
        else
          [
            distance_matrix[a_index - 1][b_index] + 1, # deletion
            distance_matrix[a_index][b_index - 1] + 1, # insertion
            distance_matrix[a_index - 1][b_index - 1] + 1 # substitution
          ].min # pick best
        end
      end
    end
    distance_matrix[a_magnitude][b_magnitude]
  end

  CHECK_DOMAINS = %w[gmail.com yahoo.com hotmail.com outlook.com uottawa.ca].freeze

  def validate_each(record, attribute, value)
    return if value.blank?

    if !value.match?(URI::MailTo::EMAIL_REGEXP)
      record.errors.add(attribute, :invalid)
    elsif options.fetch(:typo_check, true)
      suggest_known_domain(record, attribute, value.split("@").last)
    end
  end

  private

  # A domain seen twice before is trusted; otherwise one within 1 to 3 edits of a
  # well-known provider is reported as a probable typo.
  def suggest_known_domain(record, attribute, domain)
    seen = Rails.cache.read("email_domain_#{domain}")
    return if seen && seen > 1
    Rails.cache.write("email_domain_#{domain}", seen.to_i + 1, expires_in: 1.day)

    return if CHECK_DOMAINS.include?(domain)
    correct_domain = CHECK_DOMAINS.find { |known| levenshtein_distance(domain, known).between?(1, 3) }
    record.errors.add(attribute, "Check your email domain. Did you mean #{correct_domain}?") if correct_domain
  end
end

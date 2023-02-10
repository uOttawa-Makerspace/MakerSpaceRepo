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

  def validate_each(record, attribute, value)
    email = value.split("@")
    return if email.size != 2

    domain = email[1]
    check_domains = %w[gmail.com yahoo.com hotmail.com outlook.com uottawa.ca]
    check_domains.each do |correct_domain|
      return if domain == correct_domain
      distance = levenshtein_distance(domain, correct_domain)
      if 1 <= distance && distance <= 4
        record.errors[
          attribute
        ] << "Check your email address. Did you mean #{correct_domain}?"
        return
      end
    end
  end
end

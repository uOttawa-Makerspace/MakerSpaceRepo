# frozen_string_literal: true

namespace :increment_year do
  desc 'increment year to students'
  task increment_one_year: :environment do
    # Get students, created this month and are not alumni and not created this year
    this_month = Date.today.month
    User.active.students.not_created_this_year.created_at_month(this_month).where.not(year_of_study: 'Alumni').find_each do |u|
      if u.year_of_study.to_i.between?(1, 7)
        u.update(year_of_study: u.year_of_study.next)
      else
        u.update(year_of_study: "Alumni")
      end
    end
  end

  desc 'fix year for students'
  task fix: :environment do
    User.active.students.not_created_this_year.find_each do |u|
      this_year = Date.today.year
      this_month = Date.today.month
      year_of_study = u.year_of_study.to_i
      year_difference = this_year - u.created_at.year
      if year_of_study.between?(1, 7)
        # If the month of creation has passed it will be the year of study + year_difference
        if u.created_at.month < this_month
          u.update(year_of_study: year_of_study + year_difference)
        else
          # Otherwise, it will be the year of study + year_difference - 1 to compensate for the fact that
          # it will get updated once again with the monthly rake
          u.update(year_of_study: year_of_study + year_difference - 1)
        end
      elsif year_of_study.between?(8, 15)
        u.update(year_of_study: "Alumni")
      else
        # If the month of creation has passed it will be the year_difference + 1
        if u.created_at.month < this_month
          u.update(year_of_study: 1 + year_difference)
        else
          # Otherwise, it will be the year_difference
          u.update(year_of_study: year_difference)
        end
      end
    end
  end
end

# -- -- -- -- --
#
# Year :
# 1-5 : 2020 - created_at time + year_of_study
# 6-15 : Alumni
# 15+: created_at time difference
#
# -- -- -- -- --
#
# Account created in July 2018, Answer: 1st year
# Actual : 3rd
#
# Account created in Aug 2018, Answer: 1st year
# Actual : 3rd (But 2nd for the fix)
#
# Account created in Sept 2018, Answer: 1st year
# Actual : 2nd
#
# Account created in Dec 2019, Answer: 1st year
# Actual : 1st
#
# Account created in Aug 2020, Answer: 1st year
# Actual : 1st (Fix shouldn't touch it)
#
# Account created in Aug 2020, Answer: 2020
# Actual : 1st (Fix shouldn't touch it)
#
# Account created in July 2018, Answer: 2018
# Actual : 3rd
#
# Account created in Nov 2018, Answer: 2018
# Actual : 3rd (But 2nd for the fix)
#
# -- -- -- -- --
# frozen_string_literal: true

namespace :increment_year do
  desc 'increment year to students'
  task increment_one_year: :environment do
    # Get students, created this month and are not alumni only
    User.active.created_this_month.where.not(year_of_study: [nil, 'Alumni']).find_each do |u|
      # Check if the year is between 0-8 (inclusive)
      if u.year_of_study.to_i.between?(0, 7)
        # Check if the account was created this year. f it wasn't, it will update by 1.
        u.update(year_of_study: u.year_of_study.next) #if u.created_at.year != Date.today.year
      else
        # If the year is more than 8 it will change to Alumni
        u.update(year_of_study: "Alumni")
      end
    end
  end

  desc 'fix year for students'
  task fix: :environment do
    User.active.where.not(student_id: nil).find_each do |u|
      # Make sure that it is a number
      if 0 < u.year_of_study.to_i
        year_difference = Date.today.strftime("%y").to_i - u.created_at.strftime("%y").to_i
        # Check if it's a the year they were on
        if u.year_of_study.between?(0, 7)
          # Check if account was created this year
          unless u.created_at.strftime("%y") == Date.today.strftime("%y")
            # If the month of creation has passed it will be the year of study + year_difference
            if u.created_at.strftime("%m").to_i < Date.today.strftime("%m").to_i
              u.update(year_of_study: u.year_of_study + year_difference)
            # Otherwise, it will be the year of study + year_difference - 1 to compensate for the fact that it will get updated once again with the monthly rake
            else
              u.update(year_of_study: u.year_of_study + year_difference - 1)
            end
          end
        elsif u.year_of_study.between?(6, 15)
          u.update(year_of_study: "Alumni")
        else
          unless u.created_at.strftime("%y") == Date.today.strftime("%y")
            # If the month of creation has passed it will be the year_difference + 1
            if u.created_at.strftime("%m").to_i < Date.today.strftime("%m").to_i
              u.update(year_of_study: 1 + year_difference)
            # Otherwise, it will be the year_difference
            else
              u.update(year_of_study: year_difference)
            end
          end
        end
      else
        u.update(year_of_study: "Alumni")
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
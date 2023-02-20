# Take the rockyou and try to authenticate with it
# Sandbox this task so it doesn't affect the rest of the app

namespace :vuln do
  desc "Try to authenticate with rockyou"
  task rockyou: :environment do
    attempts = 0
    # Regex minimum of 8 characters long and use at least one capital letter, one lowercase letter, and one digit.
    regex = /^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)[a-zA-Z\d]{8,}$/
    File.open("/home/ubuntu/rockyou.txt", "r") do |f|
      f.each_line do |line|
        line.chomp!
        if line =~ regex
          User
            .where("email LIKE '%@gmail.com'")
            .find_each do |user|
              attempts += 1
              if User.authenticate(user.email, line)
                puts "Found password for #{user.email}: #{line}"
              end
            end
        end
      end
    end
  end
end

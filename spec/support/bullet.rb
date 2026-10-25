# spec/support/bullet.rb
# frozen_string_literal: true

if defined?(Bullet) && Bullet.enable?
  RSpec.configure do |config|
    config.around(:each) do |example|
      if example.metadata[:skip_bullet] || example.metadata[:bullet] == false
        # Bullet::Rack still instruments (and raises for) every request while
        # Bullet is enabled, so skipping Bullet.profile is not enough: switch
        # it off for the example. Used for pinned N+1s (see defects.md D-PERFnn).
        begin
          Bullet.enable = false
          example.run
        ensure
          Bullet.enable = true
        end
      else
        Bullet.profile { example.run }
      end
    end
  end
end

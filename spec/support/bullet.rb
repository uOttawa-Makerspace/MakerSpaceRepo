# spec/support/bullet.rb
# frozen_string_literal: true

if defined?(Bullet) && Bullet.enable?
  RSpec.configure do |config|
    config.around(:each) do |example|
      if example.metadata[:skip_bullet] || example.metadata[:bullet] == false
        example.run
      else
        Bullet.profile { example.run }
      end
    end
  end
end
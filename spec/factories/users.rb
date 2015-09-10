require 'faker'

FactoryGirl.define do 
	factory :user do
		username { Faker::Internet.user_name(nil,%w(-)) }
		email { Faker::Internet.email }
		password { Faker::Internet.password }
	end
end
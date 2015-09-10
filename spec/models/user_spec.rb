require 'spec_helper'

describe User do 
	it 'is a valid username and email' do 
		user = User.new( username: "tucker1991", email: "menelik1991@gmail.com", password: "CoolPeople12" )
		expect(user).to be_valid
	end
	it 'is invalid without an username' do 
		user = User.new( username: nil, email: "menelik1991@gmail.com", password: "CoolPeople12" )
		expect(user).to_not have(1).errors_on(:username)
	end
	# it 'is invalid without an email'
end
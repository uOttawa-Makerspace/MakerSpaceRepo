
require 'faraday'

def start
	# conn = Faraday.new(:url => 'http://makerepo.com')

	# conn.post do |req|
	# 	req.url '/rfid/card_number'
	# 	req.headers = {"Content-Type" => "application/json", "Accept" => "application/json"}
	# 	req.body = { rfid: 'temp' }.to_json
	# end

	Faraday.post("http://makerepo.com/rfid/card_number", {rfid: "something"})
end

start()
require 'test_helper'

class LabSessionTest < ActiveSupport::TestCase

	test "array" do 
		lab = LabSession.new
		array1 = lab.create_array
		array2 = [[980190962, "Bob", "bob@gmail.com", "science"],
 				  [298486374, "Mary", "mary@gmail.com", "engineering"],
 				  [113629430, "Bob", "bob@gmail.com", "science"]]		

		assert_equal( array2 , array1, "Not Equal")
	end
end
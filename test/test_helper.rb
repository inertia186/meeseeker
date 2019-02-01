$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)

require 'simplecov'

SimpleCov.start
SimpleCov.merge_timeout 3600

require 'meeseeker'
require 'minitest/autorun'
require 'minitest/line/describe_track'
require 'minitest/hell'
require 'minitest/proveit'
require 'pry'

class Minitest::Test
  parallelize_me!
end

class Meeseeker::Test < MiniTest::Test
  defined? prove_it! and prove_it!
end

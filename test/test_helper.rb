$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)

require 'simplecov'

SimpleCov.start
SimpleCov.merge_timeout 3600

require 'meeseeker'
require 'mock_redis'
require 'minitest/autorun'
require 'minitest/line/describe_track'
require 'minitest/hell'
require 'minitest/proveit'
require 'pry'

# In order to test Rakefile:
gem_dir = File.expand_path("..", File.dirname(__FILE__))
$LOAD_PATH.unshift gem_dir

pwd = Dir.pwd
Dir.chdir(gem_dir)
Rake.application.init
Rake.application.load_rakefile
Dir.chdir(pwd)

class Minitest::Test
  parallelize_me!
end

class Meeseeker::Test < MiniTest::Test
  defined? prove_it! and prove_it!
end

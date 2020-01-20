require 'test_helper'
require 'rake'

module Meeseeker
  class MeeseekerTest < Meeseeker::Test
    def setup
      gem_dir = File.expand_path("..", File.dirname(__FILE__))
      $LOAD_PATH.unshift gem_dir

      pwd = Dir.pwd
      Dir.chdir(gem_dir)
      Rake.application.init
      Rake.application.load_rakefile
      Dir.chdir(pwd)
      
      begin
        if !!Meeseeker.redis.get(Meeseeker::LAST_BLOCK_NUM_KEY)
          fail "Found existing keys.  Please use 'rake reset' to enable this test."
        end
      rescue Redis::CannotConnectError => e
        puts "Cannot connect to redis, using MockRedis instead."
        
        Meeseeker.redis = MockRedis.new  
      end
    end
    
    def test_verify_all_jobs
      max_blocks = 30 # must be at least 15 to get past irreversible
      
      begin
        assert Rake::Task['verify:block_org'].invoke(max_blocks)
        assert Rake::Task['verify:steem_engine_block_org'].invoke(max_blocks)
        assert Rake::Task['verify:witness:schedule'].invoke(max_blocks)
      rescue Redis::TimeoutError => e
        skip "Timed out."
      end
      
      Rake::Task['reset'].invoke
    end
  end
end

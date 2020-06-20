require 'test_helper'
require 'rake'

module Meeseeker
  class MeeseekerTest < Meeseeker::Test
    def setup
      @max_blocks = 30 # must be at least 15 to get past irreversible
    end
    
    def test_verify_hive_jobs
      chain = 'hive'
      check_keys(chain)
      keys = []
      
      begin
        Rake::Task['verify:block_org'].reenable
        assert Rake::Task['verify:block_org'].invoke('hive', @max_blocks)
      rescue SystemExit => e
        puts 'Exited.'
      rescue Redis::TimeoutError => e
        skip 'Timed out.'
      end
        
      begin
        Rake::Task['verify:witness:schedule'].reenable
        assert Rake::Task['verify:witness:schedule'].invoke('hive', @max_blocks)
      rescue SystemExit => e
        puts 'Exited.'
      rescue Redis::TimeoutError => e
        skip 'Timed out.'
      end
        
      block_api = Hive::BlockApi.new(url: 'http://anyx.io')
      keys = Meeseeker.redis.keys('hive:*')
      data = keys.map do |key|
        next if key == 'hive:meeseeker:last_block_num'
        
        n, b, t, i, o = key.split(':')
        
        assert_equal 'hive', n, "expected hive key, got: #{key}"
        
        [b, t]
      end.compact.sample(10).to_h
      
      assert data.any?, 'expect hive data'
      
      data.each do |b, t|
        block_api.get_block(block_num: b) do |result|
          block = result.block
          
          refute_nil block, "did not expect nil block (#{b})"
          
          if !!block.transaction_ids
            assert block.transaction_ids.include?(t), "Could not find hive trx_id (#{t}) in block (#{b})."
          else
            puts "Skipped check for hive trx_id (#{t}) in block (#{b}) because API does not support lookup."
          end
        end
      end
      
      if keys.any?
        dropped = Meeseeker.redis.del(*keys)
        puts "Dropped #{dropped} keys."
      else
        fail 'No keys.'
      end
    end
    
    def test_verify_steem_jobs
      chain = 'steem'
      check_keys(chain)
      keys = []
      
      begin
        Rake::Task['verify:block_org'].reenable
        assert Rake::Task['verify:block_org'].invoke('steem', @max_blocks)
      rescue SystemExit => e
        puts 'Exited.'
      rescue Redis::TimeoutError => e
        skip 'Timed out.'
      end
      
      begin
        Rake::Task['verify:witness:schedule'].reenable
        assert Rake::Task['verify:witness:schedule'].invoke('steem', @max_blocks)
      rescue SystemExit => e
        puts 'Exited.'
      rescue Redis::TimeoutError => e
        skip 'Timed out.'
      end
      
      block_api = Steem::BlockApi.new
      keys = Meeseeker.redis.keys('steem:*')
      data = keys.map do |key|
        next if key == 'steem:meeseeker:last_block_num'
        
        n, b, t, i, o = key.split(':')
        
        assert_equal 'steem', n, "expected steem key, got: #{key}"
        
        [b, t]
      end.compact.sample(10).to_h
      
      assert data.any?, 'expect steem data'
      
      data.each do |b, t|
        block_api.get_block(block_num: b) do |result|
          block = result.block
          
          refute_nil block, "did not expect nil block (#{b})"
          
          if !!block.transaction_ids
            assert block.transaction_ids.include?(t), "Could not find steem trx_id (#{t}) in block (#{b})."
          else
            puts "Skipped check for steem trx_id (#{t}) in block (#{b}) because API does not support lookup."
          end
        end
      end
      
      if keys.any?
        dropped = Meeseeker.redis.del(*keys)
        puts "Dropped #{dropped} keys."
      else
        fail 'No keys.'
      end
    end
    
    def test_verify_steem_engine_jobs
      chain = 'steem_engine' 
      check_keys(chain)
      keys = []
      
      begin
        Rake::Task['verify:steem_engine_block_org'].reenable
        Rake::Task['verify:engine_block_org'].reenable
        assert Rake::Task['verify:steem_engine_block_org'].invoke(@max_blocks)
      rescue SystemExit => e
        puts 'Exited.'
      rescue Redis::TimeoutError => e
        skip 'Timed out.'
      end
      
      begin
        Rake::Task['verify:steem_engine_ref_blocks'].reenable
        Rake::Task['verify:engine_ref_blocks'].reenable
        assert Rake::Task['verify:steem_engine_ref_blocks'].invoke(@max_blocks)
      rescue SystemExit => e
        puts 'Exited.'
      rescue Redis::TimeoutError => e
        skip 'Timed out.'
      end
      
      agent = Meeseeker::SteemEngine::Agent.new
      keys = Meeseeker.redis.keys('steem_engine:*')
      data = keys.map do |key|
        n, b, t, i, o = key.split(':')
        
        assert_equal chain, n, "expected steem_engine key, got: #{key}"
        
        next if t == Meeseeker::VIRTUAL_TRX_ID
        
        [b, t]
      end.compact.sample(10).to_h
      
      assert data.any?, 'expect steem_engine data'
      
      data.each do |b, t|
        block = agent.block(b)
        refute_nil block, "did not expect nil block (#{b})"
        
        count = block['transactions'].select do |trx|
          trx['transactionId'].include? t
        end.size
        
        assert count > 0, "Could not find steem_engine trx_id (#{t}) in block (#{b})."
      end
      
      agent.shutdown
      
      if keys.any?
        dropped = Meeseeker.redis.del(*keys)
        puts "Dropped #{dropped} keys."
      else
        fail 'No keys.'
      end
    end
    
    def test_verify_hive_engine_jobs
      chain = 'hive_engine'
      check_keys(chain)
      keys = []
      
      begin
        Rake::Task['verify:hive_engine_block_org'].reenable
        Rake::Task['verify:engine_block_org'].reenable
        assert Rake::Task['verify:hive_engine_block_org'].invoke(@max_blocks)
      rescue SystemExit => e
        puts 'Exited.'
      rescue Redis::TimeoutError => e
        skip 'Timed out.'
      end
      
      begin
        Rake::Task['verify:hive_engine_ref_blocks'].reenable
        Rake::Task['verify:engine_ref_blocks'].reenable
        assert Rake::Task['verify:hive_engine_ref_blocks'].invoke(@max_blocks)
      rescue SystemExit => e
        puts 'Exited.'
      rescue Redis::TimeoutError => e
        skip 'Timed out.'
      end
      
      agent = Meeseeker::HiveEngine::Agent.new
      keys = Meeseeker.redis.keys('hive_engine:*')
      data = keys.map do |key|
        n, b, t, i, o = key.split(':')
        
        assert_equal chain, n, "expected hive_engine key, got: #{key}"
        
        next if t == Meeseeker::VIRTUAL_TRX_ID
        
        [b, t]
      end.compact.sample(10).to_h
      
      assert data.any?, 'expect hive_engine data'
      
      data.each do |b, t|
        block = agent.block(b)
        refute_nil block, "did not expect nil block (#{b})"
        
        count = block['transactions'].select do |trx|
          trx['transactionId'].include? t
        end.size
        
        assert count > 0, "Could not find hive_engine trx_id (#{t}) in block (#{b})."
      end
      
      agent.shutdown
      
      if keys.any?
        dropped = Meeseeker.redis.del(*keys)
        puts "Dropped #{dropped} keys."
      else
        fail 'No keys.'
      end
    end
  private
    def check_keys(chain)
      chain = chain_key_prefix = chain.to_s
      Meeseeker.node_url = case chain.to_sym
      when :hive_engine then Meeseeker.shuffle_node_url('hive')
      when :steem_engine then Meeseeker.shuffle_node_url('steem')
      else
        Meeseeker.shuffle_node_url(chain.to_s)
      end
      
      begin
        if !!Meeseeker.redis.get(chain_key_prefix + Meeseeker::LAST_BLOCK_NUM_KEY_SUFFIX)
          fail "Found existing keys.  Please use 'rake reset' to enable this test."
        end
      rescue Redis::CannotConnectError => e
        warn "Cannot connect to redis, using MockRedis instead."
        
        Meeseeker.redis = MockRedis.new  
      end
    end
  end
end

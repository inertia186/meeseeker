require "bundler/gem_tasks"
require "rake/testtask"
require 'meeseeker'

defined? Thread.report_on_exception and Thread.report_on_exception = true

Rake::TestTask.new(:test) do |t|
  t.libs << 'test'
  t.libs << 'lib'
  t.test_files = FileList['test/**/*_test.rb']
  t.ruby_opts << if ENV['HELL_ENABLED']
    '-W2'
  else
    '-W1'
  end
end

task :default => :test

task :console do
  exec "irb -r meeseeker -I ./lib"
end

desc 'Build a new version of the meeseeker gem.'
task :build do
  exec 'gem build meeseeker.gemspec'
end

desc 'Publish the current version of the meeseeker gem.'
task :push do
  exec "gem push meeseeker-#{Meeseeker::VERSION}.gem"
end

desc 'Build a new version of the meeseeker docker image.'
task :docker_build do
  exec 'docker build -t inertia/meeseeker:latest .'
end

desc 'Publish the current version of the meeseeker docker image.'
task :docker_push do
  exec 'docker push inertia/meeseeker:latest'
end

task :check_schema do
  begin
    abort 'Unable to ping redis source.' unless Meeseeker.redis.ping == 'PONG'
  rescue Redis::CommandError => e
    puts e
  rescue Redis::CannotConnectError => e
    puts e
  end
end

task(:sync, [:chain, :at_block_num] => [:check_schema]) do |t, args|
  chain = (args[:chain] || 'steem').to_sym
  
  job = case chain
  when :steem
    Meeseeker::BlockFollowerJob.new
  when :steem_engine
    Meeseeker::SteemEngine::FollowerJob.new
  else; abort("Unknown chain: #{chain}")
  end
  
  job.perform(at_block_num: args[:at_block_num])
end

namespace :witness do
  desc 'Publish the witness schedule every minute or so (steem:witness:schedule).'
  task :schedule do
    job = Meeseeker::WitnessScheduleJob.new
    job.perform
  end
end

task(:find, [:what, :key, :chain] => [:check_schema]) do |t, args|
  chain = (args[:chain] || 'steem').downcase.to_sym
  redis = Meeseeker.redis
  
  match = case args[:what].downcase.to_sym
  when :block then "#{chain}:#{args[:key]}:*"
  when :trx then "#{chain}:*:#{args[:key]}:*"
  else; abort "Unknown lookup using #{args}"
  end

  puts "Looking for match on: #{match}"
  keys = redis.keys(match)
  
  keys.each do |key|
    puts key
    puts redis.get(key)
  end
end

task :reset, [:chain] => [:check_schema] do |t, args|
  chain = (args[:chain] || 'all').to_sym
  keys = []
  
  print 'Dropping keys for set: %s ...' % chain.to_s
  
  case chain
  when :steem, :all then keys += Meeseeker.redis.keys('steem:*')
  when :steem_engine, :all then keys += Meeseeker.redis.keys('steem_engine:*')
  end
  
  if keys.any?
    print " found #{keys.size} keys ..."
    dropped = Meeseeker.redis.del(*keys)
    puts " dropped #{dropped} keys."
  else
    puts ' nothing to drop.'
  end
end

namespace :verify do
  desc 'Verifies transactions land where they should.'
  task :block_org, [:max_blocks] do |t, args|
    max_blocks = args[:max_blocks]
    node_url = ENV.fetch('MEESEEKER_NODE_URL', 'https://api.steemit.com')
    database_api = Steem::DatabaseApi.new(url: node_url)
    mode = ENV.fetch('MEESEEKER_STREAM_MODE', 'head').to_sym
    until_block_num = if !!max_blocks
      database_api.get_dynamic_global_properties do |dgpo|
        raise 'Got empty dynamic_global_properties result.' if dgpo.nil?
        
        case mode
        when :head then dgpo.head_block_number
        when :irreversible then dgpo.last_irreversible_block_num
        else; abort "Unknown block mode: #{mode}"
        end
      end + max_blocks.to_i
    end
    
    Thread.new do
      job = Meeseeker::BlockFollowerJob.new
      
      loop do
        begin
          job.perform(mode: mode, until_block_num: until_block_num)
        rescue => e
          puts e.inspect
          sleep 5
        end
        
        break # success
      end
      
      puts 'Background sync finished ...'
    end
    
    begin
      block_api = Steem::BlockApi.new(url: node_url)
      block_channel = 'steem:block'
      redis_url = ENV.fetch('MEESEEKER_REDIS_URL', 'redis://127.0.0.1:6379/0')
      subscription = Redis.new(url: redis_url)
      ctx = Redis.new(url: redis_url)
      timeout = (max_blocks).to_i * 3
      
      subscribe_mode, subscribe_args = if timeout > 0
        [:subscribe_with_timeout, [timeout, [block_channel]]]
      else
        [:subscribe, [[block_channel]]]
      end
      
      subscription.send(subscribe_mode, *subscribe_args) do |on|
        on.subscribe do |channel, subscriptions|
          puts "Subscribed to ##{channel} (subscriptions: #{subscriptions})"
        end
        
        on.message do |channel, message|
          payload = JSON[message]
          block_num = payload['block_num']
          expected_witness = payload['witness']
          next_block_num = block_num + 1
          
          if !!max_blocks
            if block_num >= until_block_num
              # We're done trailing blocks.  Typically, this is used by unit
              # tests so the test can halt.
              
              subscription.unsubscribe
              next
            end
          end
            
          while ctx.keys("steem:#{next_block_num}:*").size == 0
            # This ensures at least the next block has been indexed before
            # proceeding.
            
            puts "Waiting for block: #{next_block_num} ..."
            sleep 6
          end
          
          database_api.get_dynamic_global_properties do |dgpo|
            raise 'Got empty dynamic_global_properties result.' if dgpo.nil?
            
            (block_num - dgpo.last_irreversible_block_num).tap do |offset|
              # This will block all channel callbacks until the first known block
              # is irreversible.  After that, the offsets should mostly go
              # negative.
              
              sleep offset * 3 if offset > 0
            end
          end
          
          # In theory, we should have all the keys using this pattern.
          keys = ctx.keys("steem:#{block_num}:*")
          
          # If we have all the keys, we should also have all transaction ids.
          expected_ids = keys.map { |k| k.split(':')[2] }.uniq
          expected_ids -= [Meeseeker::VIRTUAL_TRX_ID]
          
          actual_ids, actual_witness = block_api.get_block(block_num: block_num) do |result|
            raise 'Got empty block result.' if result.nil? || result.block.nil?
            
            block = result.block
            [block.transaction_ids, block.witness]
          end
          
          # We do an intersection to make sure there's no difference between
          # the two copies, regardless of order, as opposed to just checking that
          # the lengths match.
          
          (actual_ids & expected_ids).tap do |intersection|
            all_sizes = [intersection.size, expected_ids.size, actual_ids.size]
            puts 'intersection: %d; expected: %d; actual: %d' % all_sizes
            
            if all_sizes.min != all_sizes.max
              puts "Expected witness: #{expected_witness}; actual witness: #{actual_witness}"
              puts "Expected transaction ids:"
              puts expected_ids
              puts "Actual transaction ids:"
              puts actual_ids
              
              puts "actual_ids minus expected:"
              puts actual_ids - expected_ids
              puts "expected_ids minus actual:"
              puts expected_ids - actual_ids
              
              exit(-1)
            end
          end
        end
        
        on.unsubscribe do |channel, subscriptions|
          puts "Unsubscribed from ##{channel} (subscriptions: #{subscriptions})"
        end
      end
    end
  end
  
  desc 'Verifies Steem Engine transactions land where they should.'
  task :steem_engine_block_org, [:max_blocks] do |t, args|
    max_blocks = args[:max_blocks]
    node_url = ENV.fetch('MEESEEKER_STEEM_ENGINE_NODE_URL', 'https://api.steem-engine.com/rpc')
    agent = Meeseeker::SteemEngine::Agent.new(url: node_url)
    until_block_num = if !!max_blocks
      agent.latest_block_info['blockNumber']
    end
    
    Thread.new do
      job = Meeseeker::SteemEngine::FollowerJob.new
      
      loop do
        begin
          at_block_num = agent.latest_block_info["blockNumber"] - max_blocks.to_i
          at_block_num = [at_block_num, 1].max
          job.perform(at_block_num: at_block_num, until_block_num: until_block_num)
        rescue => e
          puts e.inspect
          sleep 5
        end
        
        break # success
      end
      
      puts 'Background sync finished ...'
    end
    
    begin
      block_channel = 'steem_engine:block'
      redis_url = ENV.fetch('MEESEEKER_REDIS_URL', 'redis://127.0.0.1:6379/0')
      subscription = Redis.new(url: redis_url)
      ctx = Redis.new(url: redis_url)
      timeout = (max_blocks).to_i * 3
      
      subscribe_mode, subscribe_args = if timeout > 0
        [:subscribe_with_timeout, [timeout, [block_channel]]]
      else
        [:subscribe, [[block_channel]]]
      end
      
      subscription.send(subscribe_mode, *subscribe_args) do |on|
        on.subscribe do |channel, subscriptions|
          puts "Subscribed to ##{channel} (subscriptions: #{subscriptions})"
        end
        
        on.message do |channel, message|
          payload = JSON[message]
          block_num = payload['block_num']
          next_block_num = block_num + 1
          
          if !!max_blocks
            if block_num >= until_block_num
              # We're done trailing blocks.  Typically, this is used by unit
              # tests so the test can halt.
              
              subscription.unsubscribe
              next
            end
          end
          
          while ctx.keys("steem_engine:#{next_block_num}:*").size == 0
            # This ensures at least the next block has been indexed before
            # proceeding.
            
            puts "Waiting for block: #{next_block_num} ..."
            sleep 6
          end
          
          # In theory, we should have all the keys using this pattern.
          keys = ctx.keys("steem_engine:#{block_num}:*")
          
          # If we have all the keys, we should also have all transaction ids.
          expected_ids = keys.map { |k| k.split(':')[2] }.uniq
          actual_ids = nil
          
          agent.block(block_num).tap do |block|
            raise 'Got empty block result.' if block.nil?
            
            actual_ids = block['transactions'].map{|trx| trx['transactionId'].split('-').first}.uniq
          end
          
          # We do an intersection to make sure there's no difference between
          # the two copies, regardless of order, as opposed to just checking that
          # the lengths match.
          
          (actual_ids & expected_ids).tap do |intersection|
            all_sizes = [intersection.size, expected_ids.size, actual_ids.size]
            puts 'intersection: %d; expected: %d; actual: %d' % all_sizes
            
            if all_sizes.min != all_sizes.max
              puts "Expected transaction ids:"
              puts expected_ids
              puts "Actual transaction ids:"
              puts actual_ids
              
              puts "actual_ids minus expected:"
              puts actual_ids - expected_ids
              puts "expected_ids minus actual:"
              puts expected_ids - actual_ids
              
              exit(-1)
            end
          end
        end
        
        on.unsubscribe do |channel, subscriptions|
          puts "Unsubscribed from ##{channel} (subscriptions: #{subscriptions})"
        end
      end
    end
  end
  
  desc 'Verifies Steem Engine sidechain against the mainnet.'
  task :steem_engine_ref_blocks do |t|
    redis_url = ENV.fetch('MEESEEKER_REDIS_URL', 'redis://127.0.0.1:6379/0')
    ctx = ctx = Redis.new(url: redis_url)
    keys = ctx.keys('steem_engine:*')
    block_api = Steem::BlockApi.new
    block_trxs = {}
    
    puts "Checking Steem Engine keys: #{keys.size}"
    
    keys.each do |key|
      transaction = JSON[ctx.get(key)]
      block_num = transaction['refSteemBlockNumber']
      
      block_trxs[block_num] ||= []
      block_trxs[block_num] << transaction['transactionId'].split('-').first
    end
    
    puts "Related mainnet blocks: #{block_trxs.keys.size}"
    
    skipped_blocks = []
    
    block_api.get_blocks(block_range: block_trxs.keys) do |block, block_num|
      if block.nil? || block[:transaction_ids].nil?
        print 'S'
        skipped_blocks << block_num
        
        next
      else
        print '.'
      end
    
      if (block.transaction_ids & block_trxs[block_num]).none?
        puts "\nNo intersection in #{block_num}!"
        puts "Expected the following sidechain trx_ids: #{block_trxs[block_num].join(', ')}"
      end
    end
    
    puts "\nBlocks to retry: #{skipped_blocks.size}"
    
    skipped_blocks.each do |block_num|
      block_api.get_block(block_num: block_num) do |result|
        block = result.block
        
        if (block.transaction_ids & block_trxs[block_num]).none?
          puts "No intersection in #{block_num}!"
          puts "Expected the following sidechain trx_ids: #{block_trxs[block_num].join(', ')}"
        end
      end
    end
    
    puts "Done."
  end
    
  namespace :witness do
    desc 'Verifies witnessses in the schedule produced a block.'
    task :schedule, [:max_blocks] do |t, args|
      max_blocks = args[:max_blocks]
      node_url = ENV.fetch('MEESEEKER_NODE_URL', 'https://api.steemit.com')
      database_api = Steem::DatabaseApi.new(url: node_url)
      mode = ENV.fetch('MEESEEKER_STREAM_MODE', 'head').to_sym
      until_block_num = if !!max_blocks
        database_api.get_dynamic_global_properties do |dgpo|
          raise 'Got empty dynamic_global_properties result.' if dgpo.nil?
          
          case mode
          when :head then dgpo.head_block_number
          when :irreversible then dgpo.last_irreversible_block_num
          else; abort "Unknown block mode: #{mode}"
          end
        end + max_blocks.to_i
      end
      
      Thread.new do
        job = Meeseeker::WitnessScheduleJob.new
        
        loop do
          begin
            job.perform(mode: mode, until_block_num: until_block_num)
          rescue => e
            puts e.inspect
            sleep 5
          end
          
          break # success
        end
        
        puts 'Background sync finished ...'
      end
    
      begin
        block_api = Steem::BlockApi.new(url: node_url)
        schedule_channel = 'steem:witness:schedule'
        redis_url = ENV.fetch('MEESEEKER_REDIS_URL', 'redis://127.0.0.1:6379/0')
        subscription = Redis.new(url: redis_url)
        ctx = Redis.new(url: redis_url)
        timeout = (max_blocks).to_i * 3
        
        subscribe_mode, subscribe_args = if timeout > 0
          [:subscribe_with_timeout, [timeout, [schedule_channel]]]
        else
          [:subscribe, [[schedule_channel]]]
        end
        
        # Check if the redis context is still available right before we
        # subscribe.
        break unless subscription.ping == 'PONG'
        
        subscription.send(subscribe_mode, *subscribe_args) do |on|
          on.subscribe do |channel, subscriptions|
            puts "Subscribed to ##{channel} (subscriptions: #{subscriptions})"
          end
          
          on.message do |channel, message|
            payload = JSON[message]
            next_shuffle_block_num = payload['next_shuffle_block_num']
            current_shuffled_witnesses = payload['current_shuffled_witnesses']
            num_witnesses = current_shuffled_witnesses.size
            from_block_num = next_shuffle_block_num - num_witnesses + 1
            to_block_num = from_block_num + num_witnesses - 1
            block_range = from_block_num..to_block_num # typically 21 blocks
            
            if !!max_blocks
              if block_range.include? until_block_num
                # We're done trailing blocks.  Typically, this is used by unit
                # tests so the test can halt.
                
                subscription.unsubscribe
              end
            end
            
            begin
              # We write witnesses to this hash until all 21 produce blocks.
              actual_witnesses = {}
              tries = 0
              
              while actual_witnesses.size != num_witnesses
                # Allow the immediate node to catch up in case it's behind by a
                # block.
                sleep 3
                
                # Typically, nodes will allow up to 50 block headers in one
                # request, if backed by jussi.  We only need 21, so each
                # request should only make a single response with the entire
                # round.  Under normal circumstances, this call happens only
                # once.  But if the there's additional p2p or cache latency,
                # it might have missing headers.
                
                block_api.get_block_headers(block_range: block_range) do |header, block_num|
                  unless !!header
                    # Can happen when there's excess p2p latency and/or jussi
                    # cache is under load.
                    puts "Waiting for block header: #{block_num}"
                    
                    next
                  end
                  
                  actual_witnesses[header.witness] = block_num
                end
                
                break if (tries += 1) > 5
              end
              
              # If there are multiple tries due to high p2p latency, even though
              # we got all 21 block headers, seeing this message could be an
              # early-warning of other problems on the blockchain.
              
              # If there's a missing block header, this will always show 5
              # tries.
              
              puts "Tries: #{tries}" if tries > 1
              
              missing_witnesses = current_shuffled_witnesses - actual_witnesses.keys
              extra_witnesses = actual_witnesses.keys - current_shuffled_witnesses
              
              if missing_witnesses.any? || extra_witnesses.any?
                puts "Expected only these witness to produce a block in #{block_range}."
                puts "Missing witnesses: #{missing_witnesses.join(', ')}"
                puts "Extra witnesses: #{extra_witnesses.join(', ')}"
                
                puts "\nWitnesses and block numbers in range:"
                actual_witnesses.sort_by{ |k, v| v }.each do |k, v|
                  puts "#{v}: #{k}"
                end
                puts "Count: #{actual_witnesses.size}"
                
                # Non-zero exit to notify the shell caller that there's a
                # problem.
                
                exit(-(missing_witnesses.size + extra_witnesses.size))
              end
            end
            
            # Perfect round.
            
            puts "Found all #{num_witnesses} expected witnesses in block range #{block_range}: √"
          end
          
          on.unsubscribe do |channel, subscriptions|
            puts "Unsubscribed from ##{channel} (subscriptions: #{subscriptions})"
          end
        end
      end
    end
  end
end

require "bundler/gem_tasks"
require "rake/testtask"
require 'meeseeker'

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

task :check_schema do
  begin
    abort 'Unable to ping redis source.' unless Meeseeker.redis.ping == 'PONG'
  rescue Redis::CommandError => e
    puts e
  rescue Redis::CannotConnectError => e
    puts e
  end
end

task(:sync, [:at_block_num] => [:check_schema]) do |t, args|
  job = Meeseeker::BlockFollowerJob.new
  job.perform(at_block_num: args[:at_block_num])
end

task(:find, [:what, :key] => [:check_schema]) do |t, args|
  redis = Meeseeker.redis
  match = case args[:what].downcase.to_sym
  when :block then "steem:#{args[:key]}:*"
  when :trx then "steem:*:#{args[:key]}:*"
  else; abort "Unknown lookup using #{args}"
  end

  puts "Looking for match on: #{match}"
  keys = redis.keys(match)
  
  keys.each do |key|
    puts key
    puts redis.get(key)
  end
end

task reset: [:check_schema] do
  print 'Dropping keys ...'
  keys = Meeseeker.redis.keys('steem:*')
  
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
    defined? Thread.report_on_exception and Thread.report_on_exception = true
    
    max_blocks = args[:max_blocks]
    node_url = ENV.fetch('MEESEEKER_NODE_URL', 'https://api.steemit.com')
    database_api = Steem::DatabaseApi.new(url: node_url)
    until_block_num = nil
    
    Thread.new do
      job = Meeseeker::BlockFollowerJob.new
      mode = ENV.fetch('MEESEEKER_STREAM_MODE', 'head').to_sym
      until_block_num = if !!max_blocks
        database_api.get_dynamic_global_properties do |dgpo|
          case mode
          when :head then dgpo.head_block_number
          when :irreversible then dgpo.last_irreversible_block_num
          else; abort "Unknown block mode: #{mode}"
          end
        end + max_blocks.to_i
      end
      
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
end

module Meeseeker::SteemEngine
  MAX_RETRY_INTERVAL = 18.0
  
  class FollowerJob
    def perform(options = {})
      redis = Meeseeker.redis
      last_key_prefix = nil
      trx_index = 0
      current_block_num = nil
      block_transactions = []
      
      stream_transactions(options) do |transaction, block|
        begin
          trx_id = transaction['transactionId'].to_s.split('-').first
          block_num = block['blockNumber']
          current_key_prefix = "steem_engine:#{block_num}:#{trx_id}"
          contract = transaction['contract']
          action = transaction['action']

          if current_key_prefix == last_key_prefix
            trx_index += 1
          else
            if !!last_key_prefix
              n, b, t = last_key_prefix.split(':')
              transaction_payload = {
                block_num: b.to_i,
                transaction_id: t,
                transaction_num: block_transactions.size
              }
              
              block_transactions << trx_id
              redis.publish('steem_engine:transaction', transaction_payload.to_json)
            end
            
            last_key_prefix = "steem_engine:#{block_num}:#{trx_id}"
            trx_index = 0
          end
          
          key = "#{current_key_prefix}:#{trx_index}:#{contract}:#{action}"
          puts key
        end

        redis.set(key, transaction.to_json)
        redis.expire(key, Meeseeker.expire_keys) unless Meeseeker.expire_keys == -1
        
        if current_block_num != block_num
          block_transactions = []
          block_payload = {
            block_num: block_num
          }
          
          redis.set(Meeseeker::LAST_STEEM_ENGINE_BLOCK_NUM_KEY, block_num)
          redis.publish('steem_engine:block', block_payload.to_json)
          current_block_num = block_num
        end
        
        redis.publish("steem_engine:#{contract}", {key: key}.to_json)
        redis.publish("steem_engine:#{contract}:#{action}", {key: key}.to_json)
      end
    end
  private
    def agent
      @agent ||= Agent.new
    end
    
    def agent_reset
      return if @agent.nil?
      
      @agent.shutdown
      @agent = nil
    end
    
    def retry_interval
      @retry_interval ||= 0.1
      @retry_interval *= 2
      
      [@retry_interval, MAX_RETRY_INTERVAL].min
    end
    
    def reset_retry_interval
      @retry_interval = nil
    end
    
    def stream_transactions(options = {}, &block)
      redis = Meeseeker.redis
      last_block_num = nil
      until_block_num = options[:until_block_num].to_i
      
      if !!options[:at_block_num]
        last_block_num = options[:at_block_num].to_i
      else
        new_sync = false
        last_block_num = redis.get(Meeseeker::LAST_STEEM_ENGINE_BLOCK_NUM_KEY)
        block_info = agent.latest_block_info
        block_num = block_info['blockNumber']
        last_block = agent.block(block_num)
        last_block_timestamp = Time.parse(last_block['timestamp'] + 'Z')
                
        if last_block_num.nil?
          new_sync = true
          last_block_num = block_num
        else
          last_block_num = last_block_num.to_i + 1
        end
        
        if Meeseeker.expire_keys == -1
          last_block_num = [last_block_num, block_num].max
          
          puts "Sync Steem Engine from: #{last_block_num}"
        elsif new_sync || (Time.now.utc - last_block_timestamp > Meeseeker.expire_keys)
          last_block_num = block_num + 1
          
          puts 'Starting new Steem Engine sync.'
        else
          puts "Resuming from Steem Engine block #{last_block_num} ..."
        end
      end
      
      block_num = last_block_num
      
      loop do
        begin
        block = agent.block(block_num)
          reset_retry_interval
        rescue Net::HTTP::Persistent::Error => e
          puts "Retrying: #{e}"
          agent_reset
          sleep retry_interval
          redo
        end
        
        if block.nil?
          sleep 3 # sleep for one mainnet block interval
          redo
        end
        
        transactions = block['transactions']
        
        transactions.each do |transaction|
          yield transaction.merge(timestamp: block['timestamp']), block
        end
        
        break if until_block_num != 0 && block_num > until_block_num
        
        block_num = block_num + 1
      end
    end
  end
end

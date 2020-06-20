module Meeseeker::SteemEngine
  MAX_RETRY_INTERVAL = 18.0
  
  class FollowerJob
    def initialize(options = {})
      @chain_key_prefix = options[:chain_key_prefix] || Meeseeker::STEEM_ENGINE_CHAIN_KEY_PREFIX
    end
    
    def chain_name
      @chain_key_prefix.split('_').map(&:capitalize).join(' ')
    end
    
    def perform(options = {})
      redis = Meeseeker.redis
      last_key_prefix = nil
      trx_index = 0
      current_block_num = nil
      block_transactions = []
      
      stream_transactions(options) do |data, block|
        transaction = data[:transaction]
        virtual = !!data[:virtual]
        
        begin
          trx_id = transaction['transactionId'].to_s.split('-').first
          block_num = block['blockNumber']
          current_key_prefix = "#{@chain_key_prefix}:#{block_num}:#{trx_id}"
          contract = transaction['contract']
          action = transaction['action']

          if current_key_prefix == last_key_prefix
            trx_index += 1
          else
            if !!last_key_prefix
              _, b, t = last_key_prefix.split(':')
              transaction_payload = {
                block_num: b.to_i,
                transaction_id: t,
                transaction_num: block_transactions.size
              }
              
              block_transactions << trx_id
              
              trx_pub_key = if !!virtual
                "#{@chain_key_prefix}:virtual_transaction"
              else
                "#{@chain_key_prefix}:transaction"
              end
              
              redis.publish(trx_pub_key, transaction_payload.to_json)
            end
            
            last_key_prefix = "#{@chain_key_prefix}:#{block_num}:#{trx_id}"
            trx_index = 0
          end
          
          key = "#{current_key_prefix}:#{trx_index}:#{contract}:#{action}"
          puts key
        end

        unless Meeseeker.max_keys == -1
          while redis.keys("#{@chain_key_prefix}:*").size > Meeseeker.max_keys
            sleep Meeseeker::BLOCK_INTERVAL
          end
        end
        
        redis.set(key, transaction.to_json)
        redis.expire(key, Meeseeker.expire_keys) unless Meeseeker.expire_keys == -1
        
        if current_block_num != block_num
          block_transactions = []
          block_payload = {
            block_num: block_num
          }
          
          redis.set(@chain_key_prefix + Meeseeker::LAST_STEEM_ENGINE_BLOCK_NUM_KEY_SUFFIX, block_num)
          redis.publish("#{@chain_key_prefix}:block", block_payload.to_json)
          current_block_num = block_num
        end
        
        redis.publish("#{@chain_key_prefix}:#{contract}", {key: key}.to_json)
        redis.publish("#{@chain_key_prefix}:#{contract}:#{action}", {key: key}.to_json)
      end
    end
  private
    def agent
      @agent ||= case @chain_key_prefix
      when 'steem_engine' then Agent.new
      when 'hive_engine' then Meeseeker::HiveEngine::Agent.new
      end
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
        last_block_num = redis.get(@chain_key_prefix + Meeseeker::LAST_STEEM_ENGINE_BLOCK_NUM_KEY_SUFFIX)
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
          
          puts "Sync #{chain_name} from: #{last_block_num}"
        elsif new_sync || (Time.now.utc - last_block_timestamp > Meeseeker.expire_keys)
          last_block_num = block_num + 1
          
          puts "Starting new #{chain_name} sync."
        else
          puts "Resuming from #{chain_name} block #{last_block_num} ..."
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
          sleep Meeseeker::BLOCK_INTERVAL
          redo
        end
        
        transactions = block['transactions']
        
        transactions.each do |transaction|
          yield({transaction: transaction.merge(timestamp: block['timestamp'])}, block)
        end
        
        virtual_transactions = block['virtualTransactions']
        
        virtual_transactions.each do |virtual_transaction|
          _, vtrx_in_block = virtual_transaction['transactionId'].split('-')
          virtual_transaction = virtual_transaction.merge(
            timestamp: block['timestamp'],
            'transactionId' => "#{Meeseeker::VIRTUAL_TRX_ID}-#{vtrx_in_block}"
          )
          
          yield({transaction: virtual_transaction, virtual: true}, block)
        end
        
        break if until_block_num != 0 && block_num > until_block_num
        
        block_num = block_num + 1
      end
    end
  end
end

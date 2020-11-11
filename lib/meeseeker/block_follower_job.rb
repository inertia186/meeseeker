require 'radiator'

module Meeseeker
  class BlockFollowerJob
    MAX_VOP_RETRY = 3
    
    def perform(options = {})
      chain = (options[:chain] || 'hive').to_sym
      url = Meeseeker.default_url(chain)
      block_api = Meeseeker.block_api_class(chain).new(url: url)
      redis = Meeseeker.redis
      last_key_prefix = nil
      trx_index = 0
      current_block_num = nil
      block_transactions = []
      chain_key_prefix = chain.to_s if !!options[:chain]
      chain_key_prefix ||= Meeseeker.default_chain_key_prefix
      
      stream_operations(options) do |op, trx_id, block_num|
        begin
          current_key_prefix = "#{chain_key_prefix}:#{block_num}:#{trx_id}"
          
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
              
              block_transactions << trx_id unless trx_id == VIRTUAL_TRX_ID
              redis.publish("#{chain_key_prefix}:transaction", transaction_payload.to_json)
            end
            last_key_prefix = "#{chain_key_prefix}:#{block_num}:#{trx_id}"
            trx_index = 0
          end
          
          op_type = if op.type.end_with? '_operation'
            op.type.split('_')[0..-2].join('_')
          else
            op.type
          end
          
          key = "#{current_key_prefix}:#{trx_index}:#{op_type}"
          puts key
        end
        
        unless Meeseeker.max_keys == -1
          while redis.keys("#{chain_key_prefix}:*").size > Meeseeker.max_keys
            sleep Meeseeker::BLOCK_INTERVAL
          end
        end
        
        redis.set(key, op.to_json)
        redis.expire(key, Meeseeker.expire_keys) unless Meeseeker.expire_keys == -1
        
        if current_block_num != block_num
          block_transactions = []
          block_payload = {
            block_num: block_num
          }
          
          if Meeseeker.include_block_header
            catch :block_header do
              block_api.get_block_header(block_num: block_num) do |result|
                if result.nil? || result.header.nil?
                  puts "Node returned empty result for block_header on block_num: #{block_num} (rate limiting?).  Retrying ..."
                  sleep Meeseeker::BLOCK_INTERVAL
                  throw :block_header
                end
                
                block_payload.merge!(result.header.to_h)
              end
            end
          end
          
          redis.set(chain_key_prefix + LAST_BLOCK_NUM_KEY_SUFFIX, block_num)
          redis.publish("#{chain_key_prefix}:block", block_payload.to_json)
          current_block_num = block_num
        end
        
        redis.publish("#{chain_key_prefix}:op:#{op_type}", {key: key}.to_json)
        
        if Meeseeker.publish_op_custom_id
          if %w(custom custom_binary custom_json).include? op_type
            id = (op["value"]["id"] rescue nil).to_s
            
            if id.size > 0
              redis.publish("#{chain_key_prefix}:op:#{op_type}:#{id}", {key: key}.to_json)
            end
          end
        end
      end
    end
  private
    def stream_operations(options = {}, &block)
      chain = (options[:chain] || 'hive').to_sym
      redis = Meeseeker.redis
      chain_key_prefix = chain.to_s if !!options[:chain]
      chain_key_prefix ||= Meeseeker.chain_key_prefix
      last_block_num = nil
      mode = options.delete(:mode) || Meeseeker.stream_mode
      options[:include_virtual] ||= Meeseeker.include_virtual
      
      if !!options[:at_block_num]
        last_block_num = options[:at_block_num].to_i
      else
        url = Meeseeker.default_url(chain)
        database_api = Meeseeker.database_api_class(chain).new(url: url)
        last_block_num = redis.get(chain_key_prefix + LAST_BLOCK_NUM_KEY_SUFFIX).to_i + 1
        
        block_num = catch :dynamic_global_properties do
          database_api.get_dynamic_global_properties do |dgpo|
            throw :dynamic_global_properties if dgpo.nil?
            
            case mode
            when :head then dgpo.head_block_number
            when :irreversible then dgpo.last_irreversible_block_num
            else; abort "Unknown stream mode: #{mode}"
            end
          end
        end
          
        if Meeseeker.expire_keys == -1
          last_block_num = [last_block_num, block_num].max
          
          puts "Sync from: #{last_block_num}"
        elsif block_num - last_block_num > Meeseeker.expire_keys / 3
          last_block_num = block_num
          
          puts 'Starting new sync.'
        else
          behind_sec = block_num - last_block_num
          behind_sec *= 3.0
          
          puts "Resuming from #{behind_sec / 60} minutes ago ..."
        end
      end
      
      begin
        url = Meeseeker.default_url(chain)
        stream_options = {chain: chain, url: url}
        stream_args = [last_block_num, mode]
        condenser_api = nil
        
        Radiator::Stream.new(stream_options).tap do |stream|
          puts "Stream begin: #{stream_options.to_json}; #{options.to_json}"
          
          # Prior to v0.0.4, we only streamed operations with stream.operations.
          
          # After v0.0.5, we stream blocks so that we can get block.timestamp,
          # to embed it into op values.  This should also reduce streaming
          # overhead since we no longer stream block_headers inder the hood.
          
          loop do
            begin
              stream.blocks(*stream_args) do |b, n, condenser_api|
                redo if b.nil?
                
                b.transactions.each_with_index do |transaction, index|
                  transaction.operations.each do |op|
                    op_value = op[1].merge(timestamp: b.timestamp)
                    
                    yield Hashie::Mash.new(type: op[0], value: op_value), b.transaction_ids[index], n
                  end
                end
                
                next unless !!Meeseeker.include_virtual
                
                retries = 0
                
                # This is where it gets tricky.  Virtual ops sometims don't show up
                # right away, especially if we're streaming on head blocks.  In that
                # situation, we might only need to wait about 1 block.  This loop
                # will likely one execute one iteration, but we have fallback logic
                # in case there are complications.
                # 
                # See: https://developers.steem.io/tutorials-recipes/virtual-operations-when-streaming-blockchain-transactions
                
                loop do
                  # TODO (HF23) Switch to account_history_api.enum_virtual_ops if supported.
                  url = Meeseeker.default_url(chain)
                  condenser_api ||= Meeseeker.condenser_api_class(chain).new(url: url)
                  condenser_api.get_ops_in_block(n, true) do |vops|
                    if vops.nil?
                      puts "Node returned empty result for get_ops_in_block on block_num: #{n} (rate limiting?).  Retrying ..."
                      vops = []
                    end
                    
                    if vops.empty? && mode != :head
                      # Usually, we just need to slow down to allow virtual ops to
                      # show up after a short delay.  Adding this delay doesn't
                      # impact overall performance because steem-ruby will batch
                      # when block streams fall behind.
                      
                      if retries < MAX_VOP_RETRY
                        retries = retries + 1
                        condenser_api = nil
                        sleep Meeseeker::BLOCK_INTERVAL * retries
                        
                        redo
                      end
                      
                      puts "Gave up retrying virtual ops lookup on block #{n}"
                      
                      break
                    end
                    
                    if retries > 0
                      puts "Found virtual ops for block #{n} aftere #{retries} retrie(s)"
                    end
                    
                    vops.each do |vop|
                      normalized_op = Hashie::Mash.new(
                        type: vop.op[0],
                        value: vop.op[1], 
                        timestamp: vop.timestamp
                      )
                      
                      yield normalized_op, vop.trx_id, vop.block
                    end
                  end
                  
                  break
                end
              end
              
              break
            rescue => e
              raise e unless e.to_s.include? 'Request Entity Too Large'
              
              # We need to tell steem-ruby to avoid json-rpc-batch on this
              # node.
              
              Meeseeker.block_api_class(chain).const_set 'MAX_RANGE_SIZE', 1
              sleep Meeseeker::BLOCK_INTERVAL
              redo
            end
          end
        end
      end
    end
  end
end

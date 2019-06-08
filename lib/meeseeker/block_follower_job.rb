module Meeseeker
  class BlockFollowerJob
    MAX_VOP_RETRY = 3
    
    def perform(options = {})
      block_api = Steem::BlockApi.new(url: Meeseeker.node_url)
      redis = Meeseeker.redis
      last_key_prefix = nil
      trx_index = 0
      current_block_num = nil
      block_transactions = []
      
      stream_operations(options) do |op, trx_id, block_num|
        begin
          current_key_prefix = "steem:#{block_num}:#{trx_id}"
          
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
              redis.publish('steem:transaction', transaction_payload.to_json)
            end
            last_key_prefix = "steem:#{block_num}:#{trx_id}"
            trx_index = 0
          end
          
          op_type = op.type.split('_')[0..-2].join('_')
          key = "#{current_key_prefix}:#{trx_index}:#{op_type}"
          puts key
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
                throw :block_header if result.nil || result.header.nil?
                
                block_payload.merge!(result.header.to_h)
              end
            end
          end
          
          redis.set(LAST_BLOCK_NUM_KEY, block_num)
          redis.publish('steem:block', block_payload.to_json)
          current_block_num = block_num
        end
        
        redis.publish("steem:op:#{op_type}", {key: key}.to_json)
        
        if Meeseeker.publish_op_custom_id
          if %w(custom custom_binary custom_json).include? op_type
            id = (op["value"]["id"] rescue nil).to_s
            
            if id.size > 0
              redis.publish("steem:op:#{op_type}:#{id}", {key: key}.to_json)
            end
          end
        end
      end
    end
  private
    def stream_operations(options = {}, &block)
      redis = Meeseeker.redis
      last_block_num = nil
      mode = options.delete(:mode) || Meeseeker.stream_mode
      options[:include_virtual] ||= Meeseeker.include_virtual
      
      if !!options[:at_block_num]
        last_block_num = options[:at_block_num].to_i
      else
        database_api = Steem::DatabaseApi.new(url: Meeseeker.node_url)
        last_block_num = redis.get(LAST_BLOCK_NUM_KEY).to_i + 1
        
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
        stream_options = {url: Meeseeker.node_url, mode: mode}
        options = options.merge(at_block_num: last_block_num)
        condenser_api = nil
        
        Steem::Stream.new(stream_options).tap do |stream|
          puts "Stream begin: #{stream_options.to_json}; #{options.to_json}"
          
          # Prior to v0.0.4, we only streamed operations with stream.operations.
          
          # After v0.0.5, we stream blocks so that we can get block.timestamp,
          # to embed it into op values.  This should also reduce streaming
          # overhead since we no longer stream block_headers inder the hood.
          
          stream.blocks(options) do |b, n|
            b.transactions.each_with_index do |transaction, index|
              transaction.operations.each do |op|
                op = op.merge(timestamp: b.timestamp)
                
                yield op, b.transaction_ids[index], n
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
              condenser_api ||= Steem::CondenserApi.new(url: Meeseeker.node_url)
              condenser_api.get_ops_in_block(n, true) do |vops|
                redo if vops.nil?
                
                if vops.empty? && mode != :head
                  # Usually, we just need to slow down to allow virtual ops to
                  # show up after a short delay.  Adding this delay doesn't
                  # impact overall performance because steem-ruby will batch
                  # when block streams fall behind.
                  
                  if retries < MAX_VOP_RETRY
                    retries = retries + 1
                    condenser_api = nil
                    sleep 3 * retries
                    
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
        end
      end
    end
  end
end

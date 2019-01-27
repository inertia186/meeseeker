module Meeseeker
  class BlockFollowerJob
    def perform(options = {})
      stream = Steem::Stream.new(url: Meeseeker.node_url, mode: Meeseeker.stream_mode)
      database_api = Steem::DatabaseApi.new(url: Meeseeker.node_url)
      redis = Meeseeker.redis
      
      if !!options[:at_block_num]
        last_block_num = options[:at_block_num].to_i
      else
        last_block_num = redis.get(LAST_BLOCK_NUM_KEY).to_i + 1
        
        database_api.get_dynamic_global_properties do |dgpo|
          block_num = case Meeseeker.stream_mode
          when :head then dgpo.last_irreversible_block_num
          when :irreversible then dgpo.last_irreversible_block_num
          else; abort "Unknown stream mode: #{Meeseeker.stream_mode}"
          end
          
          if block_num - last_block_num > Meeseeker.expire_keys / 3
            last_block_num = block_num
            
            puts 'Starting new sync.'
          else
            behind_sec = block_num - last_block_num
            behind_sec *= 3.0
            
            puts "Resuming from #{behind_sec / 60} minutes ago ..."
          end
        end
      end
      
      options = {
        at_block_num: last_block_num,
        include_virtual: Meeseeker.include_virtual
      }
      
      if !!last_block_num
        puts options.to_json
      end
      
      last_key_prefix = nil
      trx_index = 0
      
      stream.operations(options) do |op, trx_id, block_num|
        current_key_prefix = "steem:#{block_num}:#{trx_id}"
        
        if current_key_prefix == last_key_prefix
          trx_index += 1
        else
          last_key_prefix = "steem:#{block_num}:#{trx_id}"
          trx_index = 0
        end
        
        op_type = op.type.split('_')[0..-2].join('_')
        key = "#{current_key_prefix}:#{trx_index}:#{op_type}"
        puts key
        redis.set(key, op.to_json)
        redis.expire(key, Meeseeker.expire_keys)
        redis.set(LAST_BLOCK_NUM_KEY, block_num)
      end
    end
  end
end

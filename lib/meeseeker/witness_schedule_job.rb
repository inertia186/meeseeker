module Meeseeker
  class WitnessScheduleJob
    def perform(options = {})
      chain = (options[:chain] || 'hive').to_sym
      chain_key_prefix = chain.to_s if !!options[:chain]
      chain_key_prefix ||= Meeseeker.default_chain_key_prefix
      url = Meeseeker.default_url(chain_key_prefix)
      database_api = Meeseeker.database_api_class(chain_key_prefix).new(url: url)
      redis = Meeseeker.redis
      mode = options.delete(:mode) || Meeseeker.stream_mode
      schedule = nil
      last_shuffle_block_num = nil
      
      loop do
        # Using hammer assignment will ensure we only request a new schedule
        # after we've published.
        
        schedule ||= catch :witness_schedule do
          database_api.get_witness_schedule do |result|
            throw :witness_schedule if result.nil?
          
            result
          end
        end
        
        next_shuffle_block_num = schedule.next_shuffle_block_num
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
        
        # Find out how far away we are from the next schedule.
        
        remaining_blocks = [next_shuffle_block_num - block_num - 1.5, 0].max
        
        # It's better for the schedule to publish a little late than to miss
        # an entire schedule, so we subtract 1.5 blocks from the total.
        # Sometimes we check a little early and sometimes we check a little
        # late.  But it all averages out.
        
        if remaining_blocks > 0
          delay = [remaining_blocks * 3.0, 0.25].max
          puts "Sleeping for #{delay} seconds (remaining blocks: #{remaining_blocks})."
          sleep delay
          next
        end
        
        # Now that we've reached the current schedule, check if we've published
        # it already.  If not, publish and reset for the next schedule.
        
        if next_shuffle_block_num != last_shuffle_block_num
          puts "next_shuffle_block_num: #{next_shuffle_block_num}; current_shuffled_witnesses: #{schedule.current_shuffled_witnesses.join(', ')}"
          redis.publish("#{chain_key_prefix}:witness:schedule", schedule.to_json)
          last_shuffle_block_num = next_shuffle_block_num
        end
        
        schedule = nil # re-enabled hammer assignment
        
        if !!options[:until_block_num]
          break if block_num >= options[:until_block_num].to_i
        end
      end
    end
  end
end

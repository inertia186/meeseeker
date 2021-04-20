require 'redis'
require 'steem'
require 'hive'

require 'meeseeker/version'
require 'meeseeker/block_follower_job'
require 'meeseeker/witness_schedule_job'
require 'meeseeker/steem_engine/agent'
require 'meeseeker/steem_engine/follower_job'
require 'meeseeker/hive_engine'

module Meeseeker
  STEEM_CHAIN_ID = '0000000000000000000000000000000000000000000000000000000000000000'
  HIVE_LEGACY_CHAIN_ID = '0000000000000000000000000000000000000000000000000000000000000000'
  HIVE_CHAIN_ID = 'beeab0de00000000000000000000000000000000000000000000000000000000'
  STEEM_CHAIN_KEY_PREFIX = 'steem'
  HIVE_CHAIN_KEY_PREFIX = 'hive'
  STEEM_ENGINE_CHAIN_KEY_PREFIX = 'steem_engine'
  HIVE_ENGINE_CHAIN_KEY_PREFIX = 'hive_engine'
  LAST_BLOCK_NUM_KEY_SUFFIX = ':meeseeker:last_block_num'
  LAST_STEEM_ENGINE_BLOCK_NUM_KEY_SUFFIX = ':meeseeker:last_block_num'
  BLOCKS_PER_DAY = 28800
  VIRTUAL_TRX_ID = '0000000000000000000000000000000000000000'
  BLOCK_INTERVAL = 3
  SHUFFLE_URL = 'shuffle'
  DEFAULT_STEEM_URL = 'https://api.steemit.com'
  DEFAULT_STEEM_FAILOVER_URLS = [
    DEFAULT_STEEM_URL,
    # 'https://steemd.minnowsupportproject.org',
    # 'https://anyx.io',
    # 'http://anyx.io',
    # 'https://steemd.privex.io',
    # 'https://api.steem.house'
  ]
  DEFAULT_HIVE_URL = 'https://api.openhive.network'
  DEFAULT_HIVE_FAILOVER_URLS = [
    DEFAULT_HIVE_URL,
    'https://api.hivekings.com',
    'https://anyx.io',
    'http://anyx.io',
    'https://techcoderx.com',
    'https://rpc.esteem.app',
    'https://hived.privex.io',
    'https://api.pharesim.me',
    'https://api.hive.blog',
    'https://rpc.ausbit.dev'
  ]
  
  def default_chain_key_prefix
    ENV.fetch('MEESEEKER_CHAIN_KEY_PREFIX', chain_key_prefix)
  end
  
  def self.chain_key_prefix
    @chain_key_prefix ||= {}
    url = default_url(HIVE_CHAIN_KEY_PREFIX)
    
    return @chain_key_prefix[url] if !!@chain_key_prefix[url]
    
    # Just use the Hive API for either chain, until we know which one we're
    # using.
    api = Hive::DatabaseApi.new(url: url)
    
    api.get_config do |config|
      @chain_key_prefix[node_url] = if !!config.HIVE_CHAIN_ID && config.HIVE_CHAIN_ID == HIVE_CHAIN_ID
        HIVE_CHAIN_KEY_PREFIX
      elsif !!config.HIVE_CHAIN_ID && config.HIVE_CHAIN_ID == HIVE_LEGACY_CHAIN_ID
        HIVE_CHAIN_KEY_PREFIX
      elsif !!config.STEEM_CHAIN_ID && config.STEEM_CHAIN_ID == STEEM_CHAIN_ID
        STEEM_CHAIN_KEY_PREFIX
      else
        config.keys.find{|k| k.end_with? '_CHAIN_ID'}.split('_').first.downcase.tap do |guess|
          warn "Guessing chain_key_prefix = '#{guess}' for unknown chain on: #{node_url}"
        end
      end
    end
  end
  
  def self.default_url(chain = default_chain_key_prefix)
    ENV.fetch('MEESEEKER_NODE_URL') do
      case chain.to_s
      when STEEM_CHAIN_KEY_PREFIX then DEFAULT_STEEM_URL
      when HIVE_CHAIN_KEY_PREFIX then DEFAULT_HIVE_URL
      else
        raise "Unknown chain: #{chain}"
      end
    end
  end
  
  @problem_node_urls = []
  
  @redis = Redis.new(url: ENV.fetch('MEESEEKER_REDIS_URL', 'redis://127.0.0.1:6379/0'))
  @node_url = default_url(ENV.fetch('MEESEEKER_CHAIN_KEY_PREFIX', HIVE_CHAIN_KEY_PREFIX))
  @steem_engine_node_url = ENV.fetch('MEESEEKER_STEEM_ENGINE_NODE_URL', 'https://api.steem-engine.net/rpc')
  @hive_engine_node_url = ENV.fetch('MEESEEKER_HIVE_ENGINE_NODE_URL', 'https://api.hive-engine.com/rpc')
  @stream_mode = ENV.fetch('MEESEEKER_STREAM_MODE', 'head').downcase.to_sym
  @include_virtual = ENV.fetch('MEESEEKER_INCLUDE_VIRTUAL', 'true').downcase == 'true'
  @include_block_header = ENV.fetch('MEESEEKER_INCLUDE_BLOCK_HEADER', 'true').downcase == 'true'
  @publish_op_custom_id = ENV.fetch('MEESEEKER_PUBLISH_OP_CUSTOM_ID', 'false').downcase == 'true'
  @expire_keys = ENV.fetch('MEESEEKER_EXPIRE_KEYS', BLOCKS_PER_DAY * BLOCK_INTERVAL).to_i
  @max_keys = ENV.fetch('MEESEEKER_MAX_KEYS', '-1').to_i
  
  extend self

  attr_accessor :redis, :node_url, :steem_engine_node_url,
    :hive_engine_node_url, :expire_keys, :max_keys, :stream_mode,
    :include_virtual, :include_block_header, :publish_op_custom_id
  
  def self.shuffle_node_url(chain = ENV.fetch('MEESEEKER_CHAIN_KEY_PREFIX', HIVE_CHAIN_KEY_PREFIX))
    chain = chain.to_s
    node_url = ENV.fetch('MEESEEKER_NODE_URL', default_url(ENV.fetch('MEESEEKER_CHAIN_KEY_PREFIX', chain)))
    return node_url unless node_url == SHUFFLE_URL
    
    @problem_node_urls = [] if rand(1..1000) == 13
    shuffle_node_url!(chain)
  end
  
  def self.api_class(chain = default_chain_key_prefix)
    case chain.to_s
    when STEEM_CHAIN_KEY_PREFIX then Steem::Api
    when HIVE_CHAIN_KEY_PREFIX then Hive::Api
    else
      raise "Unknown chain: #{chain}"
    end
  end
  
  def self.condenser_api_class(chain = default_chain_key_prefix)
    case chain.to_s
    when STEEM_CHAIN_KEY_PREFIX then Steem::CondenserApi
    when HIVE_CHAIN_KEY_PREFIX then Hive::CondenserApi
    else
      raise "Unknown chain: #{chain}"
    end
  end
  
  def self.block_api_class(chain = default_chain_key_prefix)
    case chain.to_s
    when STEEM_CHAIN_KEY_PREFIX then Steem::BlockApi
    when HIVE_CHAIN_KEY_PREFIX then Hive::BlockApi
    else
      raise "Unknown chain: #{chain}"
    end
  end
  
  def self.database_api_class(chain = default_chain_key_prefix)
    case chain.to_s
    when STEEM_CHAIN_KEY_PREFIX then Steem::DatabaseApi
    when HIVE_CHAIN_KEY_PREFIX then Hive::DatabaseApi
    else
      raise "Unknown chain: #{chain}"
    end
  end
  
  def self.stream_class(chain = default_chain_key_prefix)
    case chain.to_s
    when STEEM_CHAIN_KEY_PREFIX then Steem::Stream
    when HIVE_CHAIN_KEY_PREFIX then Hive::Stream
    else
      raise "Unknown chain: #{chain}"
    end
  end
  
  def self.shuffle_node_url!(chain = ENV.fetch('MEESEEKER_CHAIN_KEY_PREFIX', HIVE_CHAIN_KEY_PREFIX))
    chain = chain.to_s
    failover_urls = case chain
      when STEEM_CHAIN_KEY_PREFIX then DEFAULT_STEEM_FAILOVER_URLS - @problem_node_urls
      when HIVE_CHAIN_KEY_PREFIX then DEFAULT_HIVE_FAILOVER_URLS - @problem_node_urls
      else; []
    end
    url = failover_urls.sample
    api = api_class(chain).new(url: url)
    
    api.get_accounts(['fullnodeupdate']) do |accounts|
      fullnodeupdate = accounts.first
      metadata = (JSON[fullnodeupdate.json_metadata] rescue nil) || {}
      
      nodes = metadata.fetch('report', []).map do |report|
        next if chain == HIVE_CHAIN_KEY_PREFIX && !report[HIVE_CHAIN_KEY_PREFIX]
        next if chain != HIVE_CHAIN_KEY_PREFIX && !!report[HIVE_CHAIN_KEY_PREFIX]
        
        report['node']
      end.compact.uniq
      
      nodes -= @problem_node_urls
      
      if nodes.any?
        nodes.sample
      else
        @node_url = failover_urls.sample
      end
    end
  rescue => e
    puts "#{url}: #{e}"
    
    @problem_node_urls << url
    failover_urls -= @problem_node_urls
    failover_urls.sample
  end
  
  shuffle_node_url! if @node_url == SHUFFLE_URL
end

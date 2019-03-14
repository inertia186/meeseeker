require 'redis'
require 'steem'

require 'meeseeker/version'
require 'meeseeker/block_follower_job'
require 'meeseeker/witness_schedule_job'
require 'meeseeker/steem_engine/agent'
require 'meeseeker/steem_engine/follower_job'

module Meeseeker
  LAST_BLOCK_NUM_KEY = 'steem:meeseeker:last_block_num'
  LAST_STEEM_ENGINE_BLOCK_NUM_KEY = 'steem:meeseeker:last_steem_engine_block_num'
  BLOCKS_PER_DAY = 28800
  VIRTUAL_TRX_ID = '0000000000000000000000000000000000000000'
  @redis = Redis.new(url: ENV.fetch('MEESEEKER_REDIS_URL', 'redis://127.0.0.1:6379/0'))
  @node_url = ENV.fetch('MEESEEKER_NODE_URL', 'https://api.steemit.com')
  @steem_engine_node_url = ENV.fetch('MEESEEKER_STEEM_ENGINE_NODE_URL', 'https://api.steem-engine.com/rpc')
  @stream_mode = ENV.fetch('MEESEEKER_STREAM_MODE', 'head').downcase.to_sym
  @include_virtual = ENV.fetch('MEESEEKER_INCLUDE_VIRTUAL', 'true').downcase == 'true'
  @include_block_header = ENV.fetch('MEESEEKER_INCLUDE_BLOCK_HEADER', 'true').downcase == 'true'
  @publish_op_custom_id = ENV.fetch('MEESEEKER_PUBLISH_OP_CUSTOM_ID', 'false').downcase == 'true'
  @expire_keys = ENV.fetch('MEESEEKER_EXPIRE_KEYS', BLOCKS_PER_DAY * 3).to_i
  
  extend self

  attr_accessor :redis, :node_url, :steem_engine_node_url, :expire_keys,
    :stream_mode, :include_virtual, :include_block_header, :publish_op_custom_id
end

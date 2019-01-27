require 'redis'
require 'steem'

require 'meeseeker/version'
require 'meeseeker/block_follower_job'

module Meeseeker
  LAST_BLOCK_NUM_KEY = 'steem:meeseeker:last_block_num'
  BLOCKS_PER_DAY = 28800
  @redis = Redis.new(url: ENV.fetch('MEESEEKER_REDIS_URL', 'redis://127.0.0.1:6379/0'))
  @node_url = ENV.fetch('MEESEEKER_NODE_URL', 'https://api.steemit.com')
  @stream_mode = ENV.fetch('MEESEEKER_STREAM_MODE', 'head').downcase.to_sym
  @include_virtual = ENV.fetch('MEESEEKER_INCLUDE_VIRTUAL', 'true').downcase == 'true'
  @expire_keys = ENV.fetch('MEESEEKER_EXPIRE_KEYS', BLOCKS_PER_DAY * 3).to_i
  
  extend self

  attr_accessor :redis, :node_url, :expire_keys, :stream_mode, :include_virtual
end

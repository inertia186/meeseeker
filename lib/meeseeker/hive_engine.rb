module Meeseeker::HiveEngine
  
  class Agent < Meeseeker::SteemEngine::Agent
    def initialize(options = {})
      super
      
      self.user_agent = Meeseeker::AGENT_ID
      self.max_history = 0
      self.default_encoding = 'UTF-8'
      
      @node_url = options[:url] || Meeseeker::hive_engine_node_url
    end
  end
  
  class FollowerJob < Meeseeker::SteemEngine::FollowerJob
    def initialize(options = {})
      @chain_key_prefix = options[:chain_key_prefix] || Meeseeker::HIVE_ENGINE_CHAIN_KEY_PREFIX
    end
  end
end

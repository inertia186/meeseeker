require 'mechanize'

module Meeseeker::SteemEngine
  class Agent < Mechanize
    POST_HEADERS = {
      'Content-Type' => 'application/json; charset=utf-8',
      'User-Agent' => Meeseeker::AGENT_ID
    }
    
    def initialize(options = {})
      super
      
      self.user_agent = Meeseeker::AGENT_ID
      self.max_history = 0
      self.default_encoding = 'UTF-8'
      
      @node_url = options[:url] || Meeseeker::steem_engine_node_url
    end
    
    def blockchain_uri
      @blockchain_uri ||= URI.parse(@node_url + '/blockchain')
    end
    
    def blockchain_http_post
      @http_post ||= Net::HTTP::Post.new(blockchain_uri.request_uri, POST_HEADERS)
    end

    def latest_block_info
      5.times do
        request_body = {
          jsonrpc: "2.0",
          method: :getLatestBlockInfo,
          id: rpc_id
        }.to_json
        
        response = request_with_entity :post, blockchain_uri, request_body, POST_HEADERS
        latest_block_info = JSON[response.body]["result"]
        
        return latest_block_info if !!latest_block_info
        
        sleep 3
      end
      
      return nil
    end

    def block(block_num)
      5.times do
        request_body = {
          jsonrpc: "2.0",
          method: :getBlockInfo,
          params: {
            blockNumber: block_num.to_i
          },
          id: rpc_id
        }.to_json
        
        response = request_with_entity :post, blockchain_uri, request_body, POST_HEADERS
        block = JSON[response.body]["result"]
        
        return block if !!block
        
        sleep 3
      end
      
      return nil
    end
  private
    def rpc_id
      @rpc_id ||= 0
      @rpc_id = @rpc_id + 1
    end
  end
end

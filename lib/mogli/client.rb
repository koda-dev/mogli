require "mogli/client/event"
require "mogli/client/user"

module Mogli
  class Client
    attr_reader :access_token
    attr_reader :default_params
    attr_reader :expiration

    include HTTParty
    include Mogli::Client::Event
    include Mogli::Client::User
    class UnrecognizeableClassError < Exception; end

    def api_path(path)
      "https://graph.facebook.com/#{path}"
    end

    def initialize(access_token = nil,expiration=nil)
      @access_token = access_token
      # nil expiration means extended access
      expiration = Time.now.to_i + 10*365*24*60*60 if expiration.nil? or expiration == 0
      @expiration = Time.at(expiration)
      @default_params = @access_token ? {:access_token=>access_token} : {}
    end

    def expired?
      expiration and expiration < Time.now
    end

    def self.create_from_code_and_authenticator(code,authenticator)
      post_data = get(authenticator.access_token_url(code))
      parts = post_data.split("&")
      hash = {}
      parts.each do |p| (k,v) = p.split("=")
        hash[k]=v
      end
      new(hash["access_token"],hash["expires"].to_s.to_i)
    end

    def self.create_from_session_key(session_key, client_id, secret)
      authenticator = Mogli::Authenticator.new(client_id, secret, nil)
      access_data = authenticator.get_access_token_for_session_key(session_key)
      new(access_data['access_token'],
          Time.now.to_i + access_data['expires'].to_i)
    end

    def post(path,klass,body_args)
      data = self.class.post(api_path(path),:body=>default_params.merge(body_args))
      map_data(data,klass)
    end

    def delete(path)
      self.class.delete(api_path(path),:query=>default_params)
    end

    def get_and_map(path,klass=nil,body_args = {})
      data = self.class.get(api_path(path),:query=>default_params.merge(body_args))
      map_data(data,klass)
    end

    def get_and_map_url(url,klass=nil)
      data = self.class.get(url)
      map_data(data,klass)
    end

    def map_data(data,klass=nil)
      raise_error_if_necessary(data)
      hash_or_array = extract_hash_or_array(data,klass)
      hash_or_array = map_to_class(hash_or_array,klass) if klass
      hash_or_array
    end

    #protected

    def extract_hash_or_array(hash_or_array,klass)
      return nil if hash_or_array == false
      return hash_or_array if hash_or_array.nil? or hash_or_array.kind_of?(Array)
      return extract_fetching_array(hash_or_array,klass) if hash_or_array.has_key?("data")
      return hash_or_array
    end

    def extract_fetching_array(hash,klass)
      f = Mogli::FetchingArray.new
      f.concat(hash["data"])
      f.client = self
      f.classes = Array(klass)
      if hash["paging"]
        f.next_url = hash["paging"]["next"]
        f.previous_url = hash["paging"]["previous"]
      end
      f
    end

    def map_to_class(hash_or_array,klass)
      return nil if hash_or_array.nil?
      if hash_or_array.kind_of?(Array)
        hash_or_array.map! {|i| create_instance(klass,i)}
      else
        hash_or_array = create_instance(klass,hash_or_array)
      end
    end

    def create_instance(klass,data)
      klass = determine_class(klass,data)
      if klass.nil?
        raise UnrecognizeableClassError.new("unable to recognize klass for #{klass.inspect} => #{data.inspect}")
      end
      klass.new(data,self)
    end

    def constantize_string(klass)
      klass.is_a?(String) ? Mogli.const_get(klass) : klass
    end

    def determine_class(klass_or_klasses,data)
      klasses = Array(klass_or_klasses).map { |k| constantize_string(k)}
      klasses.detect {|klass| klass.recognize?(data)} || klasses.first
    end

    def raise_error_if_necessary(data)
      if data.kind_of?(Hash)
        if data.keys.size == 1 and data["error"]
          type = data["error"]["type"]
          message = data["error"]["message"]
          raise Exception.new("#{type}: #{message}")
        end
      end
    end

    def fields_to_serialize
      [:access_token,:default_params,:expiration]
    end

    # Only serialize the bare minimum to recreate the session.
    def marshal_load(variables)#:nodoc:
      fields_to_serialize.each_with_index{|field, index| instance_variable_set("@#{field}", variables[index])}
    end

    # Only serialize the bare minimum to recreate the session.
    def marshal_dump#:nodoc:
      fields_to_serialize.map{|field| send(field)}
    end

    # Only serialize the bare minimum to recreate the session.
    def to_yaml( opts = {} )#nodoc
      YAML::quick_emit(self.object_id, opts) do |out|
        out.map(taguri) do |map|
          fields_to_serialize.each do |field|
            map.add(field, send(field))
          end
        end
      end
    end

  end
end

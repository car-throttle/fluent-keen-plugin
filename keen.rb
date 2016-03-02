require 'json'
require 'uri'
require 'net/http'
require 'net/https'
#
# Yay Fluent!
#
module Fluent
  #
  # Here be a set of classes for interacting with Keen as an API client
  #
  module KeenClient
    #
    # The Error class just handles errors returned from the HTTP class
    # It's important that we log the original payload too, for sanity purposes
    #
    class Error < StandardError
      attr_reader :res, :req_params

      def initialize(res, req_params = {})
        @res = res
        @req_params = req_params.dup
      end

      def message
        "res.code:#{@res.code}, res.body:#{@res.body}, req_params:#{@req_params}"
      end

      alias :to_s :message
    end
    #
    # The Request class actually makes the HTTP requests
    # It's designed to live as long as the Fluent instances runs for
    #
    class Request
      attr_accessor :debug_keen, :log, :log_events
      attr_reader :api_url, :project_id, :write_key

      def initialize(project_id, write_key)
        @api_url = 'https://api.keen.io/3.0/projects'
        @project_id = project_id
        @write_key = write_key
      end

      def post(payload)
        debug_on = false
        debug_on = true if @debug_keen
        debug_on = true if (!!@log_events and @log_events.include?(payload['tag']))

        log.info 'Processing tag ' + payload['tag'] + ' : ' + payload['time'].to_s if debug_on

        url = URI.parse('%s/%s/events/%s?api_key=%s' % [
          @api_url,
          @project_id,
          payload['tag'],
          @write_key
        ])

        http = Net::HTTP.new(url.host, url.port)
        http.use_ssl = (url.scheme == 'https')
        http.verify_mode = OpenSSL::SSL::VERIFY_NONE

        headers = {
          'Accept' => 'application/json',
          'Content-Type' => 'application/json',
          'Host' => url.host,
          'User-Agent' => 'fluent-plugin-keen'
        }

        #log.info url if debug_on
        #log.info headers if debug_on
        #log.info payload['record'] if debug_on

        res = http.post(url.request_uri, payload['record'], headers)
        raise Error.new(res, payload) unless res.code == '201'

        log.info 'Sent tag ' + payload['tag'] + ' : ' + payload['time'].to_s if debug_on
      end

    end
    #
  end
  #
  # The KeenOutput class will be instantiated by Fluent for actual use
  #
  class KeenOutput < Fluent::BufferedOutput
    Fluent::Plugin.register_output('keen', self)

    # For fluentd v0.12.16 or earlier
    class << self
      unless method_defined?(:desc)
        def desc(description)
        end
      end
    end

    desc 'The project ID you received from Keen when setting up your project'
    config_param :project_id, :string, default: nil

    desc 'The write key you received from Keen when setting up your project'
    config_param :write_key, :string, default: nil

    desc 'If specified, this plugin will print debug information'
    config_param :debug_keen, :bool, default: false

    desc 'If specified, the state of these logs will be printed in the fluent log when processed'
    config_param :log_events, default: nil do |val|
      val.split(',')
    end

    def configure(conf)
      super

      raise ConfigError, '"project_id" parameter is required for keen' unless @project_id
      raise ConfigError, '"write_key" parameter is required for keen' unless @write_key

      $log.info "debug_keen has been enabled" if @debug_keen

      @request = Fluent::KeenClient::Request.new(project_id, write_key)
      @request.log = $log

      @request.debug_keen = @debug_keen
      @request.log_events = @log_events if @log_events
    end

    def format(tag, time, record)
      [tag, time, record].to_msgpack
    end

    def write(chunk)
      begin
        payloads = []

        chunk.msgpack_each do |tag, time, record|
          payloads << {
            'tag' => tag.split('.').last,
            'time' => time,
            'record' => JSON.dump(record)
          }
        end

        payloads.each {|payload| @request.post(payload) }
      rescue Timeout::Error => e
        log.warn 'keen:', :error => e.to_s, :error_class => e.class.to_s
        raise e # and let Fluentd retry
      rescue => e
        log.error 'keen:', :error => e.to_s, :error_class => e.class.to_s
        log.warn_backtrace e.backtrace
        # discarded.. perhaps we should log the entire payload?
      end
    end

  end
end
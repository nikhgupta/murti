require 'pry'
require 'time'
require 'exif'
require 'exiftool'
require 'xxhash'
require "find"
require "murti/version"
require "murti/configuration"
require "murti/processor"

module Murti
  class Error < StandardError; end
  CONFIG_PATH = "#{ENV['HOME']}/.murti.conf.rb"
  STRATEGIES = %i[test copy move]

  class << self
    attr_reader :config

    def raise!(message)
      raise Error.new(message)
    end

    def debug(message)
      puts message if ENV['DEBUG']
    end

    def info(message)
      puts "[INFO]: #{message}"
    end

    def load_or_raise_if_no_config!(options)
      path = options[:config] || CONFIG_PATH
      error = "No configuration found in #{path}"

      if File.readable?(path)
        load path
        source = config.sources_for(options)
        target = config.target_for(options)
        if source.empty? || !target
          raise! error
        end
      else
        raise! error
      end
    end

    def valid_strategy?(name)
      STRATEGIES.include?(name.to_sym)
    end

    def configure(&block)
      raise! "You need a block to configure Murti!" unless block_given?
      conf = Murti::Configuration.new
      conf.instance_eval(&block)
      @config = conf
    end

    def run(src=nil, options={})
      processor = Murti::Processor.new options
      sources = [src].flatten.compact
      sources = Murti.config.sources_for(options) if sources.empty?
      sources.each do |src|
        puts "[INFO]: Organizing #{src}"
        Find.find(src).each do |path|
          next if File.directory?(path)
          processor.process path, src
          while Murti.config.added.any?
            processor.process Murti.config.added.pop, src
          end
        end
      end
    end
  end
end

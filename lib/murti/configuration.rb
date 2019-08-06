module Murti
  class Configuration
    attr_reader :strategy, :formats, :blocks, :added

    def initialize
      @strategy = :test
      @blocks = {skip: [], extract: [], rule: []}
      @formats = {date: "%Y-%m-%d", new: "%{basename}%{extname}", existing: "%{basename}-%{index}%{extname}"}
      @added, @groups, @last_group = [], {}, nil
    end

    def group(name=:default, &block)
      @last_group = name ? name.to_s.downcase.to_sym : :default
      instance_eval(&block)
      @last_group = nil
    end

    def source_directory(path, on: :always)
      Murti.raise! "source_directory should be placed inside a group!" if !@last_group
      @groups[@last_group] ||= {}
      @groups[@last_group][:source] ||= {}
      @groups[@last_group][:source][path] = on
    end

    def target_directory(path)
      Murti.raise! "target_directory should be placed inside a group!" if !@last_group
      @groups[@last_group] ||= {}
      @groups[@last_group][:target] = path
    end

    def sources_for(options={})
      group = options.fetch(:group, :default).to_s.downcase.to_sym
      Murti.raise! "Group: #{group} not defined?" unless @groups.key?(group)
      sources = @groups[group][:source]
      return sources.keys if options.fetch(:refresh, false)
      sources.reject{|k,v| v.to_s.downcase.to_sym == :refresh}.keys
    end

    def target_for(options={})
      group = options.fetch(:group, :default).to_s.downcase.to_sym
      Murti.raise! "Group: #{group} not defined?" unless @groups.key?(group)
      @groups[group][:target]
    end

    def use_strategy(name)
      Murti.raise "Invalid strategy: #{name}" if !Murti.valid_strategy?(name)
      @strategy = name
    end

    def add_file(src)
      @added << src
    end

    def set_date_format(format)
      @formats[:date] = format
    end

    def rename_file_to(format)
      @formats[:new] = format
    end

    def rename_file_with_duplicate_name_to(format)
      @formats[:existing] = format
    end

    def skip_if(*args, &block)
      @blocks[:skip] << [args, block]
    end

    def extract(*args, &block)
      @blocks[:extract] << [args, block]
    end

    def rule(*args, &block)
      @blocks[:rule] << [args, block]
    end
  end
end

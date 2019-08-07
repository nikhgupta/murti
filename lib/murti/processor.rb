module Murti
  class Processor
    attr_reader :path, :exif, :options

    def initialize(options={})
      @blocks = Murti.config.blocks
      @formats = Murti.config.formats
      @options = options
    end

    def reset_for(path, source)
      @path, @destination, @source = path, {}, source
      @ext = File.extname(path).gsub(/^\./, '').downcase
      @skipped, @matched, @timestamp, @exif_date = false, false, nil, nil
      @basename = File.basename(path)
      @dup_counter, @exist_counter = 0, 0
      @migrate_blocks = []
    end

    def process(path, source)
      reset_for path, source

      @blocks[:skip].each do |sb|
        run_hook :skip_if, *sb[0], sb[1]
      end
      return if @skipped

      @exif = fetch_exif_data(path)
      @exif = fetch_exif_data_alt(path) if @exif.empty?

      @blocks[:extract].each do |sb|
        run_hook :extract, *sb[0], sb[1]
      end

      @blocks[:rule].each do |sb|
        run_hook :process_file_if, *sb[0], sb[1]
      end

      migrate_file
    end

    def run_hook(group, *args, block)
      hash = args.last.is_a?(Hash) ? args.pop : {}
      if args.empty? && hash.empty?
        send group, &block
      elsif args.empty?
        hash.each do |key, val|
          method = "#{group}_#{key}"
          Murti.raise! "Invalid config: #{group} #{key} #{val}" unless respond_to?(method)
          send(method, val, &block)
        end
      else
        args.each do |arg|
          method = "#{group}_#{arg}"
          Murti.raise! "Invalid config: #{group} #{arg}" unless respond_to?(method)
          send(method, hash, &block)
        end
      end
    end

    def save_in(format)
      @destination[:base] = get_format(format)
    end

    def save_prefix(format)
      @destination[:prefix] = get_format(format)
    end

    def save_suffix(format)
      @destination[:suffix] = get_format(format)
    end

    def skip_if_hidden(*)
      return if @skipped
      @skipped = @basename =~ /\A\..*\z/
      Murti.debug "#{path} => [SKIP] - HIDDEN" if @skipped
    end

    def skip_if_extension(*extensions)
      return if @skipped
      @skipped = has_extension?(*extensions)
      Murti.debug "#{path} => [SKIP] - EXTENSION" if @skipped
    end

    def skip_if_extension_not_in(*extensions)
      return if @skipped
      @skipped = !has_extension?(*extensions)
      Murti.debug "#{path} => [SKIP] - EXTENSION" if @skipped
    end

    def skip_if_name(regex)
      return if @skipped
      @skipped = @basename =~ regex
      Murti.debug "#{path} => [SKIP] - NAME MATCHED" if @skipped
    end

    def skip_if_path(regex)
      return if @skipped
      @skipped = path =~ regex
      Murti.debug "#{path} => [SKIP] - PATH MATCHED" if @skipped
    end

    def skip_if(&block)
      return if @skipped
      @skipped = block.call(path)
      Murti.debug "#{path} => [SKIP] - CUSTOM" if @skipped
    end

    def extract_timestamp(options={}, &block)
      options.each do |key, val|
        send("extract_timestamp_from_#{key}", val, &block)
      end
    end

    def extract_timestamp_from_name(regex, &block)
      return if @timestamp
      match = @basename.match(regex)
      return unless match
      time = block.call(match[1..-1])
      @timestamp = time.is_a?(Time) ? time : Time.parse(time)
    rescue StandardError
    end

    def extract_timestamp_from_exif(strategy=:oldest, &block)
      return if @exif.empty?
      dates = @exif
        .select{|k,v| v =~ /\A\d+:\d+:\d+(?:| \d+:\d+:\d+)\z/ || v.is_a?(Time) || v.is_a?(Date)}
        .reject{|k,v| k =~ /^(file|profile|modify|metadata)_/}

      if dates.empty?
        @exif = fetch_exif_data_alt(path)
        dates = @exif
          .select{|k,v| v =~ /\A\d+:\d+:\d+(?:| \d+:\d+:\d+)\z/ || v.is_a?(Time) || v.is_a?(Date)}
          .reject{|k,v| k =~ /^(file|profile|modify|metadata)_/} if !@exif.empty?
      end

      return if dates.empty?
      dates = dates.map{|k,v| [k, parse_exif_timestamp(v)]}.to_h

      case strategy
      when :oldest then @exif_date = dates.values.min
      when :latest then @exif_date = dates.values.max
      when :occurrence
        fields = %i[date_time_original date_time create_date gps_date_stamp date_time_digitized]
        @exif_date = fields.map{|f| dates[f]}.compact.first
      end
      # binding.pry if !@exif_date
    end

    def extract_timestamp_from_path(regex, &block)
      return if @timestamp
      match = path.match(regex)
      return unless match
      time = block.call(match)
      @timestamp = time.is_a?(Time) ? time : Time.parse(time)
    rescue StandardError
    end

    def process_file_if_extension(*extensions, &block)
      return if @matched
      matched = has_extension?(*extensions)
      if matched
        @matched = { extension: matched }
        instance_eval(&block)
      end
    end

    def process_file_if_valid_date(options={}, &block)
      return if @matched || (!@timestamp && !@exif_date)
      return if options[:extension] && !has_extension?(options[:extension])
      return if options[:name_regex] && !(@basename =~ options[:name_regex])
      return if options[:path_regex] && !(path =~ options[:name_regex])

      @timestamp ||= @exif_date
      @timestamp = @exif_date if @exif_date && @timestamp.to_date != @exif_date.to_date
      @matched = { date: @timestamp }.merge(options)
      instance_eval(&block)
    end

    def process_file_if_name_regex(regex, &block)
      return if @matched
      match = @basename.match(regex)
      if match
        @matched = { name_regex: regex }
        instance_eval(&block)
      end
    end

    def process_file_if_path_regex(regex, &block)
      return if @matched
      match = path.match(regex)
      if match
        @matched = { path_regex: regex }
        instance_eval(&block)
      end
    end

    def process_file_if_is_unmatched(*, &block)
      return if @matched
      @matched = { unmatched: true }
      instance_eval(&block)
    end

    def process_file_if_is_duplicate(*, &block)
      return unless @matched
      @matched = { duplicate: true }
      @duplicate_block = block
    end

    def process_file_if(&block)
      return if @matched
      @matched = { custom: true }
      instance_eval(&block)
    end

    def migrate(&block)
      @migrate_blocks << block
    end

    def add_file_for_migration(src)
      Murti.config.add_file(src)
      puts "[+ADD]: #{path} => #{src}"
    end

    def duplicate_number
      @dup_counter
    end

    def remove!
      FileUtils.rm path
      puts "[-DEL]: #{path} => #{dest}"
    end

    def migrate_file
      dest = [@destination[:prefix], @destination[:base], @destination[:suffix]]
      dest = dest.reject{|a| a.to_s.strip.empty?}
      name = get_formatted_file_name(exist_counter: @exist_counter)
      dest = File.join(Murti.config.target_for(group: options[:group]), *dest, name)
      return if path == dest
      return unless File.exist?(path)

      strategy = %i[test move copy].detect{|k| options[k]}
      strategy = Murti.config.strategy if !strategy

      if identical_to?(dest)
        @dup_counter += 1
        instance_eval(&@duplicate_block)
        migrate_file
      elsif File.exist?(dest)
        @exist_counter += 1
        migrate_file
      elsif strategy == :test
        puts "[TEST]: #{path} => #{dest}"
      elsif strategy == :copy
        @migrate_blocks.each{ |mb| instance_eval(&mb) }
        FileUtils.mkdir_p(File.dirname(dest))
        begin
          FileUtils.cp(path, dest)
          puts "[COPY]: #{path} => #{dest}"
        rescue Errno::EIO
          Murti.info "[FAIL]: #{path} => #{dest}"
        end
      elsif strategy == :move
        @migrate_blocks.each{ |mb| instance_eval(&mb) }
        FileUtils.mkdir_p(File.dirname(dest))
        begin
          FileUtils.mv(path, dest)
          puts "[MOVE]: #{path} => #{dest}"
        rescue Errno::EIO
          Murti.info "[FAIL]: #{path} => #{dest}"
        end
        FileUtils.rm(path) if File.exist?(path)
        begin
          FileUtils.rmdir(File.dirname(path))
        rescue Errno::ENOTEMPTY
        end
      end
    end

    private

    def parse_exif_timestamp(o)
      return o if o.is_a?(Time)
      return o.to_date if o.is_a?(Date)
      ts   = Time.parse(o) rescue nil
      ts ||= Time.strptime(o, "%Y:%m:%d %H:%M:%S") rescue nil
      ts ||= Time.strptime(o, "%Y:%m:%d:%H:%M:%S") rescue nil
      ts ||= Time.strptime(o, "%Y:%m:%d") rescue nil
    end

    def has_extension?(extensions=[])
      extensions.detect do |sext|
        (sext.is_a?(Regexp) && @ext =~ sext) || @ext == sext.to_s
      end
    end

    def get_formatted_file_name(name: nil, exist_counter: 0)
      data = { basename: File.basename(path, '.*'), extname: File.extname(path) }
      data[:index] = exist_counter
      name ||= exist_counter > 0 ? @formats[:existing] : @formats[:new]
      name % data
    end

    def identical_to?(dest)
      return false unless File.exist?(dest)
      return false unless File.readable?(dest)
      Murti.debug "Finding hashes for: #{path}, #{dest}"
      fetch_file_hash(path) == fetch_file_hash(dest)
    end

    def get_format(format)
      data = {basename: File.basename(path, '.*'), extname: File.extname(path)}
      data[:date_format] = get_date_format

      base = format.split("%{path_component}").first
      target = File.join(Murti.config.target_for(group: options[:group]), base)
      pac = path.start_with?(target) ? target.chomp("/") : @source.chomp("/")
      data[:path_component] = File.dirname(path).gsub(/^#{Regexp.escape(pac)}\/?/, '')

      format % data
    end

    def get_date_format
      return unless @timestamp
      @timestamp.strftime(@formats[:date])
    end

    def fetch_exif_data(path)
      Exif::Data.new(File.open(path)).ifds.map{|k,v| v.to_a}.flatten(1).to_h rescue {}
    end

    def fetch_exif_data_alt(path)
      Exiftool.new(path).to_hash rescue {}
    end

    def fetch_file_hash(path, seed=12345678)
      @hashes ||= {}
      @hashes[path] ||= XXhash.xxh32_stream(File.open(path), seed)
      @hashes[path]
    end
  end
end

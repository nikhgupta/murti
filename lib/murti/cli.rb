require 'thor'

module Murti
  class CLI < Thor
    method_option :config, type: :string, default: "#{ENV['HOME']}/.murti.conf.rb"
    method_option :refresh, type: :boolean, default: false, description: "Re-organize existing files, as well."
    method_option :test, type: :boolean, default: false, description: "Use test strategy - just show me what will happen!"
    method_option :move, type: :boolean, default: false, description: "Move the files from source to target."
    method_option :copy, type: :boolean, default: false, description: "Copy the files from source to target."
    method_option :group, type: :string, default: "default", description: "Group of source/target directories to organize."
    desc 'organize [SRC]', 'Organize photos in [src] to [dest]'
    def organize(src=nil)
      Murti.load_or_raise_if_no_config!(options)
      Murti.run(src, options)
    end
  end
end

require 'yaml'
require 'singleton'

module TomatoToot
  class Config < Hash
    include Singleton

    def initialize
      super
      dirs.each do |dir|
        suffixes.each do |suffix|
          Dir.glob(File.join(dir, "*#{suffix}")).each do |f|
            key = File.basename(f, suffix)
            self[key] = YAML.load_file(f) unless self[key]
          end
        end
      end
      raise 'ローカル設定が見つかりません。' unless self['local']
    end

    def dirs
      return [
        File.join('/usr/local/etc', File.basename(ROOT_DIR)),
        File.join('/etc', File.basename(ROOT_DIR)),
        File.join(ROOT_DIR, 'config'),
      ]
    end

    def suffixes
      return ['.yaml', '.yml']
    end
  end
end

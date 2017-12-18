require 'yaml'

module TomatoToot
  class Config < Hash
    def initialize
      super
      Dir.glob(File.join(ROOT_DIR, 'config', '*.yaml')).each do |f|
        self[File.basename(f, '.yaml')] = YAML.load_file(f)
      end
      raise 'local.yamlが見つかりません。' unless self['local']
    end
  end
end

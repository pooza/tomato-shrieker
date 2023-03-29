module TomatoShrieker
  class Config < Ginseng::Config
    include Package
    def load
      super
      suffixes.each do |suffix|
        Dir.glob(File.join(Environment.dir, 'config/sources', "*#{suffix}")).each do |f|
          key = File.basename(f, suffix)
          values = YAML.load_file(f)
          values['id'] ||= key
          self['/sources'].push(values)
        end
      end
    end
  end
end

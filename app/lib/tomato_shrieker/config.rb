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

    def secure_dump
      return filter(raw.dig('application', 'sources'))
    end

    private

    def filter(arg)
      case arg
      in Hash
        arg.deep_stringify_keys!
        arg.each do |k, v|
          next if v.to_s.empty?
          if k == 'password'
            arg.delete(k)
          else
            arg[k] = filter(v)
          end
        end
      in Array
        arg.each_with_index do |v, i|
          next if v.to_s.empty?
          arg[i] = filter(v)
        end
      else
      end
      return arg
    end
  end
end

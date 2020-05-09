module TomatoToot
  class Config < Ginseng::Config
    include Package

    def [](key)
      keys = [key]
      (raw['deprecated'] || []).each do |entry|
        next unless entry['key'] == key
        keys.concat(entry['aliases'])
        break
      end
      keys.each do |k|
        value = super(k)
        return value unless value.nil?
      rescue Ginseng::ConfigError
        next
      end
      raise Ginseng::ConfigError, "'#{key}' not found"
    end
  end
end

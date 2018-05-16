require 'tomato-toot/config'

module TomatoToot
  module Package
    def self.name
      return self.to_s.underscore.split('/').first
    end

    def self.version
      return Config.instance['application']['package']['version']
    end

    def self.url
      return Config.instance['application']['package']['url']
    end

    def self.full_name
      return "#{name} #{version}"
    end
  end
end

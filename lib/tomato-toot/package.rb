require 'tomato-toot/config'

module TomatoToot
  module Package
    def self.name
      return Config.instance['application']['package']['name']
    end

    def self.version
      return Config.instance['application']['package']['version']
    end

    def self.url
      return Config.instance['application']['package']['url']
    end

    def self.full_name
      return "#{self.name} #{self.version}"
    end
  end
end

module TomatoToot
  module Package
    def environment_class
      return 'TomatoToot::Environment'
    end

    def package_class
      return 'TomatoToot::Package'
    end

    def config_class
      return 'TomatoToot::Config'
    end

    def logger_class
      return 'TomatoToot::Logger'
    end

    def self.name
      return 'tomato-toot'
    end

    def self.version
      return Config.instance['/package/version']
    end

    def self.url
      return Config.instance['/package/url']
    end

    def self.full_name
      return "#{name} #{version}"
    end

    def self.user_agent
      return "#{name}/#{version} (#{url})"
    end
  end
end

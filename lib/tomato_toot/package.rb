module TomatoToot
  module Package
    def module_name
      return 'TomatoToot'
    end

    def environment_class
      return "#{module_name}::Environment"
    end

    def package_class
      return "#{module_name}::Package"
    end

    def config_class
      return "#{module_name}::Config"
    end

    def logger_class
      return "#{module_name}::Logger"
    end

    def http_class
      return "#{module_name}::HTTP"
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

require 'bundler/setup'
require 'tomato_shrieker/refines'

module TomatoShrieker
  using Refines

  def self.dir
    return File.expand_path('../..', __dir__)
  end

  def self.loader
    config = YAML.load_file(File.join(dir, 'config/autoload.yaml'))
    loader = Zeitwerk::Loader.new
    loader.inflector.inflect(config['inflections'])
    loader.push_dir(File.join(dir, 'app/lib'))
    loader.collapse('app/lib/tomato_shrieker/*')
    return loader
  end

  def self.setup_sentry
    dsn = Config.instance['/sentry/dsn']
    return unless dsn
    Sentry.init do |config|
      config.dsn = dsn
      config.release = Package.version
      config.environment = Environment.type
      config.traces_sample_rate = Config.instance['/sentry/traces_sample_rate'] || 0
    end
  rescue => e
    warn "Sentry initialization skipped: #{e.message}"
  end

  def self.setup_debug
    Ricecream.disable
    return unless Environment.development?
    require 'pp'
    Ricecream.enable
    Ricecream.include_context = true
    Ricecream.colorize = true
    Ricecream.prefix = "#{Package.name} | "
    Ricecream.define_singleton_method(:arg_to_s, proc {|v| PP.pp(v)})
  end

  def self.load_tasks
    finder = Ginseng::FileFinder.new
    finder.dir = File.join(dir, 'app/task')
    finder.patterns.push('*.rb')
    finder.patterns.push('*.rake')
    finder.exec.each {|f| require f}
  end

  Dir.chdir(dir)
  ENV['BUNDLE_GEMFILE'] = File.join(dir, 'Gemfile')
  Bundler.require
  loader.setup
  setup_sentry
  setup_debug
  ENV['RACK_ENV'] ||= Environment.type
  RubyVM::YJIT.enable if Environment.jit?
end

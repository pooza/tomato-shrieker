require 'bundler/setup'
require 'tomato_shrieker/refines'
require 'ginseng'

module TomatoShrieker
  def self.dir
    return File.expand_path('../..', __dir__)
  end

  def self.setup_bootsnap
    Bootsnap.setup(
      cache_dir: File.join(dir, 'tmp/cache'),
      development_mode: Environment.development?,
      load_path_cache: true,
      autoload_paths_cache: true,
      compile_cache_iseq: true,
      compile_cache_yaml: true,
    )
  end

  def self.loader
    config = YAML.load_file(File.join(dir, 'config/autoload.yaml'))
    loader = Zeitwerk::Loader.new
    loader.inflector.inflect(config['inflections'])
    loader.push_dir(File.join(dir, 'app/lib'))
    loader.collapse('app/lib/tomato_shrieker/*')
    return loader
  end

  def self.connect_dbms
    require 'sequel'
    Sequel.connect(Environment.dsn)
  end

  def self.load_tasks
    Dir.glob(File.join(dir, 'app/task/*.rb')).sort.each do |f|
      require f
    end
  end
end

Bundler.require
TomatoShrieker.loader.setup
TomatoShrieker.setup_bootsnap
TomatoShrieker.connect_dbms

require 'bootsnap'
require 'sequel'
require 'ginseng'

module TomatoToot
  def self.dir
    return File.expand_path('../..', __dir__)
  end

  def self.bootsnap
    Bootsnap.setup(
      cache_dir: File.join(dir, 'tmp/cache'),
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
    loader.collapse('app/lib/tomato_toot/*')
    return loader
  end

  def self.load_tasks
    Dir.glob(File.join(dir, 'app/task/*.rb')).sort.each do |f|
      require f
    end
  end
end

TomatoToot.bootsnap
TomatoToot.loader.setup
Bundler.require

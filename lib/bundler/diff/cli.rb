require 'bundler'
require 'rubygems'
require 'rubygems/package'
require 'optparse'
require 'pathname'
require 'tmpdir'

module Bundler::Diff::CLI
  extend self

  def run(args=ARGV)
    Bundler.ui = Bundler::UI::Shell.new

    args = option_parser.parse(args) unless args.empty?

    gem_name = args.first

    error('gem name required') unless gem_name

    bundled_spec = bundled_specs[gem_name]

    error('gem spec not found') unless bundled_spec

    Dir.mktmpdir do |tmp_dir|
      gem_spec = fetch(gem_name, tmp_dir)

      unpack(gem_spec, tmp_dir)

      def gem_spec.gem_dir; Pathname(tmp_dir).join(gem_spec.full_name); end

      Bundler::Diff::Tool.diff(bundled_spec, gem_spec)
    end
  end

  private

  def options
    @options ||= {
      version: Gem::Requirement.default
    }
  end

  def option_parser
    OptionParser.new do |opts|
      opts.banner = 'Usage: bundle diff GEMNAME [options]'

      opts.on '-h', '--help' do
        puts "#{opts}\n"

        Kernel::exit
      end

      opts.on '-v', '--version VERSION', 'Specify version of gem to diff against' do |value|
        options[:version] = Gem::Requirement.new(value)
      end
    end
  end

  def bundled_specs
    @bundled_specs ||= Bundler.load.specs.each_with_object({}) do |spec, hash|
      next if ignore?(spec)

      hash[spec.name] = spec
    end
  end

  def ignore?(spec)
    case spec.source
    when Bundler::Source::Path, Bundler::Source::Git
      true
    else
      false
    end
  end

  def fetch(name, target_dir)
    dependency = Gem::Dependency.new(name, options[:version])

    specs_and_sources, errors = Gem::SpecFetcher.fetcher.spec_for_dependency(dependency)

    spec, source = specs_and_sources.max_by { |s,| s.version }

    error('gem spec not found') if spec.nil?

    Dir.chdir(target_dir) { source.download(spec) }

    spec
  end

  def unpack(spec, tmp_dir)
    gem_file = File.join(tmp_dir, spec.full_name + '.gem')

    security_policy = nil

    package = Gem::Package.new(gem_file, security_policy)
    package.extract_files(File.join(tmp_dir, spec.full_name))
  end

  def error(message)
    Bundler.ui.error('ERROR: ' + message)

    Kernel::exit(1)
  end
end

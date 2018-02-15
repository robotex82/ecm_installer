#!/usr/bin/env ruby
require "thor"
require "open3"
require "pry"

BUNDLER_VARS = %w(BUNDLE_GEMFILE RUBYOPT BUNDLE_BIN_PATH)
module Bundler
  def self.with_clean_env &blk
    bundled_env = ENV.to_hash
    BUNDLER_VARS.each{ |var| ENV.delete(var) }
    yield
  ensure
    ENV.replace(bundled_env.to_hash)     
  end
end

module Ecm
  class PluginGenerator < Thor::Group
    include Thor::Actions

    attr_accessor :original_plugin_name

    def self.source_root
      Pathname.new(File.dirname(__FILE__)).join('plugin_generator')
    end

    def self.partials_root
      source_root.join('partials')
    end

    def self.templates_root
      source_root.join('templates')
    end

    # Define arguments and options
    argument :plugin_name

    def store_original_plugin_name
      @original_plugin_name = plugin_name
      @plugin_name = nil
    end

    ###########################################################################
    # Plugin generation
    ###########################################################################

    def generate_plugin
      `rails plugin new #{plugin_name} --skip-test --full --mountable --dummy-path=spec/dummy`
    end

    def rename_plugin
      FileUtils.mv(plugin_name, underscore(plugin_name))
    end

    ###########################################################################
    # Add spec setup to gemspec
    ###########################################################################

    def add_spec_setup_to_gemspec
      insert_into_file plugin_root.join("#{underscore(plugin_name)}.gemspec"), :before => "\nend" do
        File.read(self.class.partials_root.join('plugin_name.gemspec', '_dependencies'))
      end
    end

    def add_configuration
      add_require("#{underscore(plugin_name)}/configuration")
      insert_into_file plugin_root.join("lib", "#{underscore(plugin_name)}.rb"), :before => "\nend" do
        "\n  extend Configuration"
      end
      template(self.class.templates_root.join('lib', 'plugin_name', 'configuration.rb'), plugin_root.join('lib', underscore(plugin_name), 'configuration.rb'))
    end

    def use_configurable_base_controller
      gsub_file "#{underscore(plugin_name)}/app/controllers/#{underscore(plugin_name)}/application_controller.rb", /< ActionController::Base/, "< #{plugin_name}::Configuration.base_controller.constantize"
    end

    ###########################################################################
    # Add install generator
    ###########################################################################

    def add_install_generator
      template('templates/lib/generators/plugin_name/install/install_generator.rb', "#{underscore(plugin_name)}/lib/generators/#{underscore(plugin_name)}/install/install_generator.rb")
      template('templates/lib/generators/plugin_name/install/templates/initializer.rb', "#{underscore(plugin_name)}/lib/generators/#{underscore(plugin_name)}/install/templates/initializer.rb")
      template('templates/lib/generators/plugin_name/install/templates/routes.source', "#{underscore(plugin_name)}/lib/generators/#{underscore(plugin_name)}/install/templates/routes.source")
    end

    ###########################################################################
    # Configure assets
    ###########################################################################
    
    def configure_assets
      gsub_file "#{underscore(plugin_name)}/app/assets/javascripts/#{underscore(plugin_name)}/application.js", /\/\/= require_tree \./, "//= require_tree ./application"
      copy_file('templates/app/assets/javascripts/plugin_name/application/.keep', "#{underscore(plugin_name)}/app/assets/javascripts/plugin_name/application/.keep")
      
      gsub_file "#{underscore(plugin_name)}/app/assets/stylesheets/#{underscore(plugin_name)}/application.css", / *= require_tree \./, " *= require_tree ./application"
      copy_file('templates/app/assets/stylesheets/plugin_name/application/.keep', "#{underscore(plugin_name)}/app/assets/stylesheets/plugin_name/application/.keep")

      template('templates/config/initializers/assets.rb', "#{underscore(plugin_name)}/config/initializers/assets.rb")
    end

    ###########################################################################
    # Configure locales
    ###########################################################################
    
    def generate_locale_files
      locales.each do |locale|
        template('templates/config/locales/locale.yml', "#{underscore(plugin_name)}/config/locales/#{locale}.yml", locale: locale)
      end
    end

    ###########################################################################
    # Deep namespace
    ###########################################################################
    
    def move_files_to_deep_namespace
      if deep_namespaced?
        Dir["#{underscore(plugin_name)}/**/*"].select { |f| File.file?(f) }.each do |old_filename|
          new_filename = old_filename.gsub("/#{underscore(plugin_name)}/", "/#{underscore(original_plugin_name)}/")
          next if new_filename == old_filename
          move_file(old_filename, new_filename)
        end
      end
    end

    def replace_deep_namespaces
      if deep_namespaced?
      end
    end

    private

    def move_file(src, dst)
      FileUtils.mkdir_p(File.dirname(dst))
      FileUtils.mv(src, dst)
    end

    def plugin_name
      @plugin_name ||= @original_plugin_name.gsub('::', '_')
    end

    def deep_namespaced?
      original_plugin_name.include?('::')
    end

    def raw_locales
      ENV.fetch('LOCALES') { 'en' }
    end

    def locales
      @locales ||= raw_locales.split(',').map(&:strip)
    end

    def plugin_root
      Pathname.new(File.dirname(__FILE__)).join(underscore(plugin_name))
    end

    def add_require(path)
      insert_into_file plugin_root.join("lib", "#{underscore(plugin_name)}.rb"), before: "require \"#{underscore(plugin_name)}/engine\"" do
        "require '#{path}'\n"
      end      
    end

    def run(command)
      puts "Executing '#{command}'"
      stdout, stderr, exit_code  = Bundler.with_clean_env { result = Open3.capture3(command) }
      puts stdout
      if exit_code.success?
        puts "  => OK"
      else
        puts "  => Failed"
        puts stderr
      end
    end

    def underscore(camel_cased_word)
      camel_cased_word.to_s.gsub(/::/, '/').
        gsub(/([A-Z]+)([A-Z][a-z])/,'\1_\2').
        gsub(/([a-z\d])([A-Z])/,'\1_\2').
        tr("-", "_").
        downcase
    end
  end
end
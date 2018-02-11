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
  class Install < Thor::Group
    include Thor::Actions

    # Define arguments and options
    argument :app_name
    class_option :ecm_rbac_user_class_name, default: 'Ecm::UserArea::User'
    class_option :generate_heroku_apps,     default: false, type: :boolean
    class_option :deploy_heroku_apps,       default: false, type: :boolean
    class_option :base_controller_class_name, default: 'Frontend::ApplicationController'

    def self.source_root
      File.dirname(__FILE__)
    end

    ###########################################################################
    # Application generation
    ###########################################################################

    def generate_rails_app
      `rails new #{app_name} -T -B`
    end

    ###########################################################################
    # RVM setup
    ###########################################################################

    def create_rvm_configuration
      # template('templates/.ruby-version', "#{app_name}/.ruby-version")
      template('templates/.ruby-gemset', "#{app_name}/.ruby-gemset")
    end

    ###########################################################################
    # Gemfile/Bundler setup
    ###########################################################################

    def create_application_gemfile
      template('templates/Gemfile.application', "#{app_name}/Gemfile.application")
    end

    def modify_gemfile
      append_to_file "#{app_name}/Gemfile" do
        "\neval_gemfile File.join(File.dirname(__FILE__), 'Gemfile.application')"
      end
    end

    def install_bundler
      run("cd #{app_name} && gem install bundler")
      # `cd #{app_name} && gem install bundler`
    end

    def bundle
      run("cd #{app_name} && bundle install")
      # `cd #{app_name} && bundle`
    end

    ###########################################################################
    # Basic application setup
    ###########################################################################

    def generate_application_version
      template('templates/lib/application/version.rb', "#{app_name}/lib/#{underscore(app_name)}/version.rb")
    end

    def generate_application_version_config
      template('templates/config/initializers/application_version.rb', "#{app_name}/config/initializers/application_version.rb")
    end

    def generate_autoload_config
      template('templates/config/initializers/autoload.rb', "#{app_name}/config/initializers/autoload.rb")
    end

    ###########################################################################
    # Advanced Application setup
    ###########################################################################

    def generate_storage_s3_config
      insert_into_file "#{app_name}/config/storage.yml", :before => '# Use rails credentials:edit to set the AWS secrets (as aws:access_key_id|secret_access_key)' do
        File.read("#{self.class.source_root}/partials/config/storage.yml/_amazon")
      end
    end

    def generate_i18n_config
      template('templates/config/initializers/i18n.rb', "#{app_name}/config/initializers/i18n.rb")
    end

    def run_active_storage_installer
      run("cd #{app_name} && bundle exec rails active_storage:install")
    end

    def generate_action_mailer_config
    end

    ###########################################################################
    # Spec setup
    ###########################################################################

    def run_rspec_installer
      run("cd #{app_name} && bundle exec rails generate rspec:install")
    end

    def modify_rspec_config
      insert_into_file "#{app_name}/spec/rails_helper.rb", after: "# Dir[Rails.root.join('spec/support/**/*.rb')].each { |f| require f }\n" do
        File.read("#{self.class.source_root}/partials/spec/rails_helper.rb/_support")
      end
    end

    def init_guard
      run("cd #{app_name} && guard init")
    end

    def generate_factory_bot_rails_config
      template('templates/spec/support/factory_bot_rails.rb', "#{app_name}/spec/support/factory_bot_rails.rb")
    end

    def generate_shoulda_matchers_config
      template('templates/spec/support/shoulda_matchers.rb', "#{app_name}/spec/support/shoulda_matchers.rb")
    end

    ###########################################################################
    # Frontend engine
    ###########################################################################

    def generate_frontend_engine
      run("cd #{app_name} && rails plugin new Frontend -T --dummy-path=spec/dummy --full --mountable")
    end

    def move_frontend_engine_to_engines_folder
      run("cd #{app_name} && mkdir ./engines && mv ./Frontend ./engines/frontend")
    end

    def modify_frontend_engine_gemspec
      gsub_file "#{app_name}/engines/frontend/frontend.gemspec", /TODO: Summary of Frontend./, "#{app_name} Frontend"
      gsub_file "#{app_name}/engines/frontend/frontend.gemspec", /  s.homepage    = "TODO"\n/, ""
      gsub_file "#{app_name}/engines/frontend/frontend.gemspec", /  s.description = "TODO: Description of Frontend."\n/, ""
      gsub_file "#{app_name}/Gemfile", /\ngem 'frontend', path: 'Frontend'/m, ''
    end

    def add_gems_to_frontend_engine
      insert_into_file "#{app_name}/engines/frontend/frontend.gemspec", before: "\nend" do
        "\n  s.add_runtime_dependency 'haml-rails'\n  s.add_runtime_dependency 'twitter-bootstrap-components-rails'"
      end
  
      insert_into_file "#{app_name}/engines/frontend/lib/frontend.rb", before: 'require "frontend/engine"' do
        "\nrequire 'haml-rails'\nrequire 'twitter_bootstrap_components_rails'\n"
      end
    end

    def add_twitter_bootstrap_components_rails_to_frontend_engine
      insert_into_file "#{app_name}/engines/frontend/app/controllers/frontend/application_controller.rb", after: "  class ApplicationController < ActionController::Base\n" do
        "    helper Twitter::Bootstrap::Components::Rails::V4::ComponentsHelper\n"
      end
    end

    def add_bootstrap_to_frontend_engine
      insert_into_file "#{app_name}/engines/frontend/frontend.gemspec", before: "\nend" do
        "\n  s.add_runtime_dependency 'bootstrap', '~> 4.0.0'\n  s.add_runtime_dependency 'jquery-rails'"
      end
      insert_into_file "#{app_name}/engines/frontend/lib/frontend.rb", before: 'require "frontend/engine"' do
        "\nrequire 'bootstrap'\nrequire 'popper_js'\n"
      end
      template('templates/engines/frontend/app/assets/stylesheets/frontend/application/bootstrap_and_overrides.scss', "#{app_name}/engines/frontend/app/assets/stylesheets/frontend/application/bootstrap_and_overrides.scss")
      gsub_file "#{app_name}/engines/frontend/app/assets/stylesheets/frontend/application.css", / \*= require_tree \./, ' *= require_tree ./application'

      insert_into_file "#{app_name}/engines/frontend/app/assets/javascripts/frontend/application.js", before: "\n//= require_tree ." do
        "\n//= require jquery3\n//= require popper\n//= require bootstrap-sprockets"
      end
    end

    def add_bootstrap_layout_to_frontend_engine
      template('templates/engines/frontend/app/views/layouts/frontend/application.haml', "#{app_name}/engines/frontend/app/views/layouts/frontend/application.haml")
    end

    def add_navigation_to_frontend_engine
      template('templates/engines/frontend/app/views/frontend/application/_navbar.haml', "#{app_name}/engines/frontend/app/views/frontend/application/_navbar.haml")
    end

    def remove_erb_layout_from_frontend_enigine
      remove_file("#{app_name}/engines/frontend/app/views/layouts/frontend/application.html.erb")
    end
      
    def add_frontend_engine_to_main_application
      append_to_file "#{app_name}/Gemfile.application", "\n\ngem 'frontend', path: './engines/frontend'"
    end

    def bundle_after_frontend_engine_installation
      run("cd #{app_name} && bundle install")
    end


    ###########################################################################
    # Heroku setup
    ###########################################################################

    def generate_buildpacks
      template('templates/.buildpacks', "#{app_name}/.buildpacks")
    end

    def generate_procfile
      template('templates/Procfile', "#{app_name}/Procfile")
    end
    
    ###########################################################################
    # Configure gems
    ###########################################################################

    def run_delayed_job_active_record_generator
      run("cd #{app_name} && bundle exec rails generate delayed_job:active_record")
    end

    def generate_active_job_config
      template('templates/config/initializers/active_job.rb', "#{app_name}/config/initializers/active_job.rb")
    end

    def generate_route_translator_config
      template('templates/config/initializers/route_translator.rb', "#{app_name}/config/initializers/route_translator.rb")
    end

    def run_friendly_id_generator
      run("cd #{app_name} && bundle exec rails generate friendly_id")
    end

    def run_simple_form_generator
      run("cd #{app_name} && bundle exec rails generate simple_form:install --bootstrap")
    end

    def generate_non_stupid_digest_assets_config
      template('templates/config/initializers/non_stupid_digest_assets.rb', "#{app_name}/config/initializers/non_stupid_digest_assets.rb")
    end

    ###########################################################################
    # ITSF Backend setup
    ###########################################################################
    def run_itsf_backend_installer
      run("cd #{app_name} && bundle exec rails generate itsf:backend:install")
    end
    
    ###########################################################################
    # ECM Modules setup
    ###########################################################################
    ECM_MODULES = %w(
      ecm_core
      ecm_blog
      ecm_cms
      ecm_comments
      ecm_contact
      ecm_links
      ecm_rbac
      ecm_tags
      ecm_translations
      ecm_user_area
    )

    ECM_BACKEND_MODULES = %w(
      ecm_core_backend
      ecm_blog_backend
      ecm_cms_backend
      ecm_comments_backend
      ecm_contact_backend
      ecm_links_backend
      ecm_rbac_backend
      ecm_tags_backend
      ecm_translations_backend
      ecm_user_area_backend
    )
    def run_ecm_installers
      (ECM_MODULES - ['ecm_rbac']).each do |name|
        generator_name = "#{name.gsub('ecm_', 'ecm:').gsub('_backend', ':backend')}:install"
        run("cd #{app_name} && BASE_CONTROLLER_CLASS_NAME=#{options[:base_controller_class_name]} bundle exec rails generate #{generator_name}")
      end
    end

    def run_ecm_backend_installers
      ECM_BACKEND_MODULES.each do |name|
        generator_name = "#{name.gsub('ecm_', 'ecm:').gsub('_backend', ':backend')}:install"
        run("cd #{app_name} && bundle exec rails generate #{generator_name}")
      end
    end

    def run_ecm_rbac_installer
      run("cd #{app_name} && BASE_CONTROLLER_CLASS_NAME=#{options[:base_controller_class_name]} ECM_RBAC_USER_CLASS_NAME=#{options[:ecm_rbac_user_class_name]} bundle exec rails generate ecm:rbac:install")
    end

    def generate_ecm_migrations
      ECM_MODULES.each do |name|
        next if name == 'ecm_core'
        task_name = "#{name}:install:migrations"
        run("cd #{app_name} && bundle exec rails #{task_name}")
      end
    end

    def add_ecm_specs
    end

    ###########################################################################
    # ECM Core setup
    ###########################################################################
    def add_ecm_core_to_frontend_application_controller
      insert_into_file "#{app_name}/engines/frontend/app/controllers/frontend/application_controller.rb", after: "  class ApplicationController < ActionController::Base\n" do
        "    helper Ecm::Core::ApplicationHelper\n"
      end
    end 

    ###########################################################################
    # ECM User Area setup
    ###########################################################################
    def add_ecm_user_area_helpers_to_application_controller
      insert_into_file "#{app_name}/app/controllers/application_controller.rb", after: "class ApplicationController < ActionController::Base\n" do
        "  helper Ecm::UserAreaHelper\n"
      end
    end

    def add_ecm_user_area_to_frontend_application_controller
      insert_into_file "#{app_name}/engines/frontend/app/controllers/frontend/application_controller.rb", after: "  class ApplicationController < ActionController::Base\n" do
        "    include Controller::CurrentUserConcern\n    include Controller::RedirectBackConcern\n    helper Ecm::UserAreaHelper\n"
      end
    end
    
    def add_authentication_to_backend_controller
      insert_into_file "#{app_name}/app/controllers/backend_controller.rb", after: "class BackendController < ApplicationController\n" do
        "  before_action :authenticate_user!\n"
      end
    end

    ###########################################################################
    # ECM RBAC setup
    ###########################################################################
    def add_authorization_to_backend_controller
      # insert_into_file "#{app_name}/app/controllers/backend_controller.rb", after: "class BackendController < ApplicationController\n" do
      #   "before_action :authorize!"
      # end
    end

    ###########################################################################
    # Database setup
    ###########################################################################

    def prepare_database
      run("cd #{app_name} && rake db:create && rake db:migrate && rake db:test:prepare")
    end

    def create_default_user
      run("cd #{app_name} && rake ecm:user_area:create_default_user")
    end

    ###########################################################################
    # ECM CMS setup
    ###########################################################################

    def run_homepage_generator
      run("cd #{app_name} && rails ecm:cms:add_homepages")
    end

    ###########################################################################
    # Git setup
    ###########################################################################

    def setup_git
      run("cd #{app_name} && git init .")
    end

    def create_initial_git_commit
      run("cd #{app_name} && git add --all && git commit -am 'Initial commit.'")
    end

    ###########################################################################
    # Heroku application setup
    ###########################################################################

    def create_heroku_staging_app
      if generate_heroku_apps?
        run("cd #{app_name} && heroku create --remote staging")
      else
        puts "Skip #{__method__}"
      end
    end

    def create_heroku_production_app
      if generate_heroku_apps?
        run("cd #{app_name} && heroku create --remote production")
      else
        puts "Skip #{__method__}"
      end
    end

    ###########################################################################
    # Deploy to heroku
    ###########################################################################

    def deploy_staging
      if deploy_heroku_apps?
        run("cd #{app_name} && git push staging master")
      else
        puts "Skip #{__method__}"
      end
    end

    def run_migration_in_staging
      if deploy_heroku_apps?
        run("cd #{app_name} && heroku run rails db:migrate --remote staging")
      else
        puts "Skip #{__method__}"
      end
    end

    def deploy_production
      if deploy_heroku_apps?
        run("cd #{app_name} && git push production master")
      else
        puts "Skip #{__method__}"
      end
    end

    def run_migration_in_production
      if deploy_heroku_apps?
        run("cd #{app_name} && heroku run rails db:migrate --remote production")
      else
        puts "Skip #{__method__}"
      end
    end

    # def create_lib_file
    #   template('templates/newgem.tt', "#{name}/lib/#{name}.rb")
    # end

    # def create_test_file
    #   test = options[:test_framework] == "rspec" ? :spec : :test
    #   create_file "#{name}/#{test}/#{name}_#{test}.rb"
    # end

    # def copy_licence
    #   if yes?("Use MIT license?")
    #     # Make a copy of the MITLICENSE file at the source root
    #     copy_file "MITLICENSE", "#{name}/MITLICENSE"
    #   else
    #     say "Shame on you…", :red
    #   end
    # end
    private

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

    def generate_heroku_apps?
      !!options[:generate_heroku_apps]
    end

    def deploy_heroku_apps?
      !!options[:deploy_heroku_apps]
    end
  end
end
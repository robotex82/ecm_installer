Rails.application.config.assets.precompile += %w( <%= underscore(plugin_name) %>.css <%= underscore(plugin_name) %>.js )
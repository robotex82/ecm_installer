module <%= plugin_name %>
  module Configuration
    def configure
      yield self

      mattr_accessor(:base_controller) { '::FrontendController' }
    end
  end
end
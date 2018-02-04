# FactoryGirl.definition_file_paths << Blorgh::Engine.root.join(*%w(spec factories))
# FactoryGirl.factories.clear
# FactoryGirl.find_definitions

RSpec.configure do |config|
  config.include FactoryGirl::Syntax::Methods
end

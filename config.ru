require File.expand_path('../config/environment', __FILE__)

use Rack::Cors do
	allow do
		origins '*'
		resource '*', headers: :any, methods: :get
	end
end

Bot.log=Bot::Log.new()
Bot::Navigation.load_addons()
Bot.nav=Bot::Navigation.new()
Giskard::FBMessengerBot.init()

run Giskard::FBMessengerBot

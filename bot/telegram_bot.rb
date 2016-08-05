# encoding: utf-8

=begin
   Copyright 2016 Telegraph-ai

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.
=end

require_relative 'navigation.rb'

module Giskard
	class TelegramBot < Grape::API
		prefix WEBHOOK_PREFIX.to_sym
		format :json
		class << self
			attr_accessor :client
		end

		helpers do
			def authorized
				headers['Secret-Key']==SECRET
			end

			def format_answer(screen)
				options={}
				if (not screen[:kbd].nil?) then
					options[:kbd]=Telegram::Bot::Types::ReplyKeyboardMarkup.new(
						keyboard:kbd,
						resize_keyboard:screen[:kbd_options][:resize_keyboard],
						one_time_keyboard:screen[:kbd_options][:one_time_keyboard],
						selective:screen[:kbd_options][:selective]
					)
				end
				options[:disable_web_page_preview]=true if screen[:disable_web_page_preview]
				options[:groupsend]=true if screen[:groupsend]
				options[:parse_mode]=screen[:parse_mode] if screen[:parse_mode]
				options[:keep_kbd]=true if screen[:keep_kbd]
				return screen,options
			end

			def send_msg(id,msg,options)
				if options[:keep_kbd] then
					options.delete(:keep_kbd)
				else
					kbd = options[:kbd].nil? ? Telegram::Bot::Types::ReplyKeyboardHide.new(hide_keyboard: true) : options[:kbd] 
				end
				lines=msg.split("\n")
				buffer=""
				max=lines.length
				idx=0
				image=false
				kbd_hidden=false
				lines.each do |l|
					next if l.empty?
					idx+=1
					image=(l.start_with?("image:") && (['.jpg','.png','.gif','.jpeg'].include? File.extname(l)))
					if image && !buffer.empty? then # flush buffer before sending image
						writing_time=buffer.length/TYPINGSPEED
						TelegramBot.client.api.send_chat_action(chat_id: id, action: "typing")
						sleep(writing_time)
						TelegramBot.client.api.sendMessage(chat_id: id, text: buffer)
						buffer=""
					end
					if image then # sending image
						TelegramBot.client.api.send_chat_action(chat_id: id, action: "upload_photo")
						TelegramBot.client.api.send_photo(chat_id: id, photo: File.new(l.split(":")[1]))
					elsif options[:groupsend] # grouping lines into 1 single message # buggy
						buffer+=l
						if (idx==max) then # flush buffer
							writing_time=l.length/TYPINGSPEED
							TelegramBot.client.api.sendChatAction(chat_id: id, action: "typing")
							sleep(writing_time)
							TelegramBot.client.api.sendMessage(chat_id: id, text: buffer, reply_markup:kbd)
							buffer=""
						end
					else # sending 1 msg for every line
						writing_time=l.length/TYPINGSPEED
						writing_time=l.length/TYPINGSPEED_SLOW if max>1
						TelegramBot.client.api.sendChatAction(chat_id: id, action: "typing")
						sleep(writing_time)
						options[:chat_id]=id
						temp_web_page_preview_disabling=false
						if l.start_with?("no_preview:") then
							temp_web_page_preview_disabling=true
							l=l.split(':',2)[1]
							options[:disable_web_page_preview]=true
						end
						options[:text]=l
						if idx<max and not kbd_hidden then
							options[:reply_markup]=Telegram::Bot::Types::ReplyKeyboardHide.new(hide_keyboard: true)
							kbd_hidden=true
						elsif (idx==max)
							options[:reply_markup]=kbd
						end
						TelegramBot.client.api.sendMessage(options)
						options.delete(:disable_web_page_preview) if temp_web_page_preview_disabling
					end
				end
			end
		end

		post '/command' do
			error!('401 Unauthorized', 401) unless authorized
			begin
				Bot::Db.init()
				update = Telegram::Bot::Types::Update.new(params)
				user,screen=Bot.nav.get(update.message,update.update_id)
				msg,options=format_answer(screen)
				send_msg(update.message.chat.id,msg,options) unless msg.nil?
			rescue Exception=>e
				Bot.log.fatal "#{e.message}\n#{e.backtrace.inspect}"
				error! "Exception raised: #{e.message}", 200 # if you put an error code here, telegram will keep sending you the same msg until you die
			ensure
				Bot::Db.close()
			end
		end

		post '/' do
			begin
				Bot::Db.init()
				update = Telegram::Bot::Types::Update.new(params)
				if update.message.chat.type=="group" then
					Bot.log.error "Message from group chat not supported:\n#{update.inspect}"
					error! "Msg from group chat not supported: #{update.inspect}", 200 # if you put an error code here, telegram will keep sending you the same msg until you die
				end
				user,screen=Bot.nav.get(update.message,update.update_id)
				msg,options=format_answer(screen)
				send_msg(update.message.chat.id,msg,options) unless msg.nil?
			rescue Exception=>e
				# Having external services called here was a VERY bad idea as exceptions would not be rescued, it would make the worker crash... good job stupid !
				Bot.log.fatal "#{e.message}\n#{e.backtrace.inspect}\n#{update.inspect}"
				if e.message.match(/blocked/).nil? and e.message.match(/kicked/).nil? then
					Giskard::TelegramBot.client.api.sendChatAction(chat_id: update.message.chat.id, action: "typing")
					Giskard::TelegramBot.client.api.sendMessage({
						:chat_id=>update.message.chat.id,
						:text=>"Oops... an unexpected error occurred #{Bot.emoticons[:confused]} Please type /start to reinitialize our discussion.",
						:reply_markup=>Telegram::Bot::Types::ReplyKeyboardHide.new(hide_keyboard: true)
					})
				end
				error! "Exception raised: #{e.message}", 200 # if you put an error code here, telegram will keep sending you the same msg until you die
			ensure
				Bot::Db.close()
			end
		end
	end
end

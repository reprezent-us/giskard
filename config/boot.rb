require 'rubygems'
require 'bundler/setup'
require_relative 'keys.local.rb'
require 'unicorn'
require 'rack/cors'
require 'grape'
require 'json'
require 'time'
require 'net/http'
require 'uri'
require 'telegram/bot'
require 'logger'
require 'ostruct'
require 'open-uri'

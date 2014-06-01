require 'bundler'
Bundler.require

require 'yaml'
YAML::ENGINE.yamler= 'syck'

require './app'
require 'nkf'
require 'open-uri'
require 'logger'

run App

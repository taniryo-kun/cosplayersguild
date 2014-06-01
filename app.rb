#coding:utf-8
require 'sinatra'
require 'sinatra/activerecord/rake'
require 'sinatra/contrib/all'
require 'sinatra/assetpack'
require 'padrino-helpers'

class App < Sinatra::Base
	set :root, File.dirname(__FILE__)

	register Sinatra::Reloader
	register Sinatra::AssetPack
	register Padrino::Helpers

	ActiveRecord::Base.configurations = YAML.load_file('database.yml')
	ActiveRecord::Base.establish_connection('development')

	before {@log = Logger.new(STDOUT)}
	after { ActiveRecord::Base.connection.close }

	assets do
		serve '/js', :from => 'assets/js'
		js :application, [
			'/js/*.js'
		]

		serve '/css', :from => 'assets/css'
		css :application, [
			'/css/*.css'
		]

		css_compression :sass
	end

	helpers do
		def protected!
			return if auth?
			headers['WWW-Authenticate'] = 'Basic realm="Restricted Area"'
			halt 401, "Not Authorized\n"
		end
		def auth?
			@auth ||= Rack::Auth::Basic::Request.new(request.env)
			@auth.provided? and @auth.basic? and @auth.credentials and @auth.credentials == ['creatersguild', 'creatersguild']
		end
	end

	class Article < ActiveRecord::Base
		validates :title, :presence => {:message => "タイトルを入力して下さい"},:uniqueness=>true
		validates :introduction, :presence => {:message => "紹介分を入力して下さい"}
		validates :url, :presence => {:message => "サイトURLを入力して下さい"},:uniqueness=>true
	end


	ActiveRecord::Base.connection_pool.with_connection do

		get '/fortest' do
			binding.pry
			redirect to '/'
		end

		get '/' do
			@article = Article.all(:conditions => {:category=>"howtomake"}, :order => "created_at DESC")
			erb :index
		end

		get '/events' do
			@events = Article.all(:conditions => {:category=>"events"}, :order => "created_at DESC")
			if @events == nil
				redirect to '/'
			else
				erb :event
			end
		end

		get '/getevents' do
			since_id = 0
			category = "events"
			client = configClient()
			@res = twitterSearch(client,"コスプレ+イベント+-RT+-Amazon.co.jp+-楽天市場 filter:links",since_id)
			savetweet(@res,category) if @res.class != Twitter::Error
			redirect to('/events')
		end

		#過去１週間以内の最新１００件取得]
		get '/gettweets' do
			since_id = 0
			category = "howtomake"
			client = configClient()
			@res = twitterSearch(client,"コスプレ+作り方+-RT filter:links",since_id)
			savetweet(@res,category) if @res.class != Twitter::Error
			redirect to('/')

			# 大量ツイート取得用
			# since_id = 0
			# counter = 0
			# while counter == 0 do
			# 	sleep(60)
			# 	client = configClient()
			# 	binding.pry
			# 	@res = twitterSearch(client,"コスプレ+作り方+-RT filter:links",since_id).reverse
			# 	@ntw = savetweet(@res) if @res.class != Twitter::Error
			# 	since_id = @ntw.tweet_id if @ntw.tweet_id != nil
			# end
		end

		get '/admin_config' do
			protected!
			@article = Article.new(:user => "CosplayersGuild", :tweet_id => "0")
			@articles = Article.find(:all, :order => "created_at DESC")
			erb :admin_config
		end

		get '/editarticle/:id' do
			@article = Article.find(params[:id])
			@articles = Article.all
			erb :admin_config
		end

		post '/createarticle' do
			@article = Article.new(params["app-article"])
			if @article.save
				redirect to('/admin_config')
			else
				#エラー事由を表示
				@articles = Article.all
				erb :admin_config
			end
		end

		post '/updatearticle' do
			@upart = Article.find(params["app-article"][:id])
			if @upart.update_attributes(params["app-article"])
				redirect to('/admin_config')
			else
				@articles = Article.all
				erb :admin_config
			end
		end

		post '/deletearticle/:id' do
			@delart = Article.find(params[:id])
			begin
				@delart.destroy
				redirect to ('/admin_config')
			rescue => e
				@log.info("raised error: #{e}")
			end
		end

		#ツイート取得結果が新規であればDB保存
		def savetweet(results,category)
			results.each do |tweet|
				twurl = geturl(tweet[:text])[0]
				if(twtitle = gettitle(twurl)) then
					#タイトル取得成功時
					if Article.find_by_title(twtitle) == nil && Article.find_by_url(twurl) == nil then
						twtext = setatag(tweet[:text])
						#エラーが発生した場合の処理
						begin
							realurl = UrlExpander::Client.expand(twurl)
						rescue => e
							@log.info("raised error: #{e}")
							realurl = twurl
						end
						@newtweet = Article.create({
							title: twtitle,
							introduction: twtext,
							user: tweet[:user][:name],
							url: realurl,
							tweet_id: tweet[:id_str],
							category: category
							})
					else
						@log.info("#{twtitle} was not saved!")
						#大量ツイート取得用
						# @last_tweet_id = tweet[:id_str]
					end
				else
					#タイトル取得エラー発生時
					@log.info("something happened to get title!")
				end
			end
			# 大量ツイート取得用
			#一巡してもセーブされたツイートがなかった場合
			# if @newtweet == nil
			# 	@newtweet = Tweet.new(:tweet_id=>@last_tweet_id)
			# end
			# return @newtweet
		end

		#文章中からURLを抽出する
		def geturl(text)
			uri_reg = URI.regexp(%w[http https])
			url 	= text.match(uri_reg)
			#urlが複数ある場合は配列として格納される
			return url
		end

		#リンク先のタイトルを取得
		def gettitle(url)
			#urlを読み込んで、
			begin
				read_data = NKF.nkf("--utf8", open(url).read)
			rescue StandardError
				@log.info("an error occurred!")
			end
			#htmlをスクレイピングしてtitleタグの中身を抽出
			title = Nokogiri::HTML.parse(read_data, nil, 'utf8').xpath('//title').text
			return title
		end 

		#文章中のurlにaタグを付加する
		def setatag(text)
			uri_reg = URI.regexp(%w[http https])
			textwtag = text.gsub!(uri_reg) {%Q{<a href="#{$&}" target="_blank">#{$&}</a>}}
			return textwtag
		end

		#文章中のurlにaタグを付けて返す
		def makelink(text)
			rtn = Hash.new()

			textwithlinks	= text.dup
			url = geturl(textwithlinks)[0]

			#URL先のtitle取得
			rtn[:linktitle]	 = gettitle(url)
			#文章内のリンク文字列にaタグ付加
			rtn[:textwlinks] = setatag(textwithlinks)

			return rtn
		end

		#twitter認証
		def configClient()
			#認証
			@client = Twitter::REST::Client.new do |config|
				config.consumer_key 		= "37ksczcL6zZLTYSvDiEg"
				config.consumer_secret 		= "vCAXYhfWlcA7kzWMW9OwkS3r08ebPqzNGiogqJRXRS8"
				config.access_token 		= "1974243638-O0Vu79nVvsh92DY6wDq61QsrgwDgBULA6EhW4qk"
				config.access_token_secret	= "oeAYmH5qcK6rud8mpiC8MbtfyIUnxxrf3agC4uGLdEius"
			end
			return @client
		end

		#twitter api 検索
		def twitterSearch(client,query,since_id)
			begin
				#検索結果を格納
				@result = client.search(query, :lang => "ja",:count => 100,:result_type => "recent",:since_id => since_id).attrs[:statuses]
				return @result
			rescue Twitter::Error => e
				print "error raised: "
				p e
			end
		end

	end
end
# -*- coding: utf-8 -*-
require 'rubygems'
require 'sinatra'
require 'RMagick'
require 'open-uri'
require 'dm-core'
require 'base64'
require 'json'
require 'rss'
require 'time'
$LOAD_PATH << 'lib'
require 'my_magick' # for RMagick 1.x
#require 'twitter_oauth'

include Magick

DataMapper::setup(:default, ENV['DATABASE_URL'] || 'sqlite3:db.sqlite3')

class Object
  def blank?
    respond_to?(:empty?) ? empty? : !self
  end

  def present?
    !self.blank?
  end
end

module URI
  # http://subtech.g.hatena.ne.jp/secondlife/20061115/1163571997
  def self.valid_http_uri?(str)
    URI.split(str).first == 'http' rescue false
  end
end

class DateTime
  def to_s_jp
    self.new_offset(Rational(9,24)).strftime("at %Y/%m/%d %H:%M:%S")
  end
end

class Photo
  include DataMapper::Resource
  property :id, Serial
  property :body, Text
  property :created_at, DateTime, :default => DateTime.now
  auto_upgrade!
end

class Member
  include DataMapper::Resource
  property :id, Serial
  property :name, String, :unique_index => :idx_member_name, :nullable => false
  auto_upgrade!
end

class Card
  include Magick

  WIDTH = 43.0
  HEIGHT = 55.0
  RIDERS = %w(decade hibiki kabuto den_o kiva kuuga agito ryuki faiz blade)

  def initialize(image)
    @image = image
  end

  def generate(user, opt, client)
    return @image if user.blank?

    begin
      src = ImageList.new(Card::image_src(user, client)).first
      src.background_color = "none"
      src.resize_to_fill!(Card::WIDTH, Card::HEIGHT).
        resize!(opt.width, opt.height).
        rotate!(opt.angle)
      @image = @image.composite(src, opt.x, opt.y, OverCompositeOp)
    rescue
      @image
    end
  end

  private
  def self.image_src(user, client)
    return URI.encode(user) if URI.valid_http_uri?(user)

    # get profile_image_url by using OAuth
    url = client.show(user)['profile_image_url']

    if url.present? and !Member.first(:name => user)
      Member.create(:name => user) rescue true
    end

    URI.encode(url)
  end
end

Setting = Struct.new(:x, :y, :width, :height, :angle)
rider_settings = {
  :decade => Setting.new(564, 171, Card::WIDTH-1, Card::HEIGHT, -2.5),

  :hibiki => Setting.new(402, 432, Card::WIDTH-18, Card::HEIGHT, 13.6),
  :kabuto => Setting.new(434, 440, Card::WIDTH-14, Card::HEIGHT, 13.6),
  :den_o =>  Setting.new(475, 447, Card::WIDTH-14, Card::HEIGHT, 13.4),
  :kiva =>   Setting.new(514, 454, Card::WIDTH-10, Card::HEIGHT, 13.4),

  :kuuga =>  Setting.new(567, 460, Card::WIDTH, Card::HEIGHT, 0),

  :agito =>  Setting.new(622, 448, Card::WIDTH, Card::HEIGHT, -12),
  :ryuki =>  Setting.new(676, 436, Card::WIDTH, Card::HEIGHT, -12),
  :faiz =>   Setting.new(737, 428, Card::WIDTH, Card::HEIGHT, -10.3),
  :blade =>  Setting.new(790, 419, Card::WIDTH, Card::HEIGHT, -10.3)
}

configure do
  use Rack::Session::Cookie, :secret => Digest::SHA1.hexdigest(rand.to_s)
  # set :sessions, true
  @@config = YAML.load_file("config.yml") rescue nil || {
    :consumer_key     => ENV['CONSUMER_KEY'],
    :consumer_secret  => ENV['CONSUMER_SECRET']
  }
end

before do
  @user = session[:user]
  @client =
    TwitterOAuth::Client.new(:consumer_key => @@config['consumer_key'],
                             :consumer_secret => @@config['consumer_secret'],
                             :token => session[:access_token],
                             :secret => session[:secret_token])
  @rate_limit_status = @client.rate_limit_status
end

get '/' do
  erb :index
end

post '/photo' do
  redirect '/connect' unless @user

  params.delete_if {|k, v| !Card::RIDERS.include?(k.to_s) }

  result = ImageList.new('images/decade.jpg')
  rider_settings.each do |k, v|
    result = Card.new(result).generate(params[k], v, @client)
  end

  image = Photo.create(:body => Base64.encode64(result.to_blob),
                       :created_at => DateTime.now)
  Photo.all(:id.lt => (image.id - 50)).each do |photo|
    photo.destroy
  end

  redirect "/show/#{image.id}"
end

delete '/photo/:id' do
  begin
    Photo.get!(params[:id]).destroy
  ensure
    redirect '/list'
  end
end

get '/photo/:id' do
  begin
    image = Photo.get!(params[:id])
    content_type :jpg
    return Base64.decode64(image.body)
  rescue
    raise Sinatra::NotFound
  end
end

get '/members.json' do
  content_type :json
  members =
    Member.find_by_sql("SELECT * FROM members ORDER BY random() LIMIT 10")
  alist = Card::RIDERS.zip(members.map{|m| m.name })
  rider_user_mapping = Hash[*alist.flatten]

  @members = JSON.unparse(rider_user_mapping)
  erb :members, :layout => false
end

post '/member' do
  begin
    unless params[:name].blank?
      Member.create(:name => params[:name].chomp)
    end
  ensure
    redirect '/'
  end
end

delete '/member' do
  member = Member.first(:name => params[:name].chomp)
  unless member.blank?
    member.destroy
  end
  redirect '/'
end

get '/show/:id' do
  begin
    image = Photo.get!(params[:id])
    @id = image.id
    erb :show
  rescue
    redirect '/'
  end
end

get '/list' do
  @photos = Photo.all(:order => [:id.desc], :limit => 50)
  erb :list
end

get '/list.rss' do
  photos = Photo.all(:order => [:id.desc], :limit => 15)
  server = "http://#{env['SERVER_NAME']}"
  if env["SERVER_PORT"] && env["SERVER_PORT"].to_i != 80
    server += ":#{env["SERVER_PORT"]}"
  end

  @rss = RSS::Maker.make("2.0") do |maker|
    maker.channel.about = server + "/"
    maker.channel.link = server + "/"
    maker.channel.title = "コンプリートフォームジェネレータ"
    maker.channel.description = "コンプリートフォームジェネレータ"
    maker.channel.date = Time.parse(photos.first.created_at.to_s)
    photos.each do |photo|
      maker.items.new_item do |item|
        item.link = server + "/show/#{photo.id}"
        item.title = "コンプリートフォーム##{photo.id}"
        item.date = Time.parse(photo.created_at.to_s)
        item.description = %Q|<img src="#{server}/photo/#{photo.id}" width="1200" height="1600" />|
      end
    end
  end

  content_type 'application/rss+xml', :charset => 'utf-8'
  erb :rss, :layout => :false
end

get '/connect' do
  request_token = @client.request_token(:oauth_callback => '')
  session[:request_token] = request_token.token
  session[:request_token_secret] = request_token.secret
  redirect request_token.authorize_url.gsub('authorize', 'authenticate')
end

get '/auth' do
  # Exchange the request token for an access token.
  @access_token = @client.authorize(
    session[:request_token],
    session[:request_token_secret],
    :oauth_verifier => params[:oauth_token]
  )

  if @client.authorized?
    session[:access_token] = @access_token.token
    session[:secret_token] = @access_token.secret
    session[:user] = true
  end

  redirect '/'
end

get '/disconnect' do
  session[:user] = nil
  session[:request_token] = nil
  session[:request_token_secret] = nil
  session[:access_token] = nil
  session[:secret_token] = nil
  redirect '/'
end

helpers do
  def h(str)
    Rack::Utils.escape_html(str)
  end
end

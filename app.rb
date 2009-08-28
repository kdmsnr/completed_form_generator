# -*- coding: utf-8 -*-
require 'rubygems'
require 'sinatra'
require 'RMagick'
require 'hpricot'
require 'open-uri'
require 'lib/my_magick' # for RMagick 1.x
require 'dm-core'
require 'base64'

include Magick

DataMapper::setup(:default, ENV['DATABASE_URL'] || 'sqlite3:db.sqlite3')

class Object
  def blank?
    respond_to?(:empty?) ? empty? : !self
  end
end

module URI
  # http://subtech.g.hatena.ne.jp/secondlife/20061115/1163571997
  def self.valid_http_uri?(str)
    URI.split(str).first == 'http' rescue false
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

  def generate(user, opt)
    return @image if user.blank?

    begin
      src = ImageList.new(image_src(user)).first
      src.background_color = "none"
      src.resize_to_fill!(Card::WIDTH, Card::HEIGHT).
        resize!(opt.width, opt.height).
        rotate!(opt.angle)
      @image = @image.composite(src, opt.x, opt.y, OverCompositeOp)
    rescue
      @image
    end
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

def image_src(user)
  case user
  when "ruby-akr"
    image = "images/akr.jpg"
  when "ruby-why"
    image = "images/_why.jpg"
  when "ruby-ko1"
    image = "images/_ko1.jpg"
  when "ruby-takahashim"
    image = "images/takahashim.jpg"
  when "ruby-matz"
    image = "images/matz.jpg"
  else
    if URI.valid_http_uri?(user)
      image = user
    else
      begin
        twitter = Hpricot(open("http://twitter.com/#{user}"))
        image = (twitter/"img#profile-image").map{|e| e['src'] }.first
        if image.blank?
          image = (twitter/"img.profile-img").map{|e| e['src'] }.first
          if image.blank?
            image = "images/twitter_bigger.png"
          end
        end
      rescue
        image = "images/twitter_bigger.png"
      end
    end
  end
  URI.encode(image)
end

def h(str)
  Rack::Utils.escape_html(str)
end

get '/' do
  erb :index
end

post '/photo' do
  params.delete_if {|k, v| !Card::RIDERS.include?(k.to_s) }

  result = ImageList.new('images/decade.jpg')
  rider_settings.each do |k, v|
    result = Card.new(result).generate(params[k], v)
  end

  Photo.all(:created_at.lt => (Time.now - 60 * 60 * 2)).each do |photo|
    photo.destroy
  end
  image = Photo.create(:body => b64encode(result.to_blob),
                       :created_at => DateTime.now)

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
    return decode64(image.body)
  rescue
    raise Sinatra::NotFound
  end
end

require 'json'
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
    raise Sinatra::NotFound
  end
end

get '/list' do
  @photos = []
  Photo.all(:order => [:id.desc]).each do |photo|
    @photos << photo
  end
  erb :list
end


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

class Photo
  include DataMapper::Resource
  property :id, Serial
  property :body, Text
  property :created_at, DateTime, :default => DateTime.now
  auto_upgrade!
end

class Card
  include Magick

  X = 43.0
  Y = 55.0

  def initialize(image)
    @image = image
  end

  def generate(user, opt)
    return @image if user.blank?

    begin
      src = ImageList.new(image_src(user)).first
      src.background_color = "none"
      src.resize_to_fill!(Card::X, Card::Y).
        resize!(opt.resized_x, opt.resized_y).
        rotate!(opt.angle)
      @image = @image.composite(src, opt.x, opt.y, OverCompositeOp)
    rescue
      @image
    end
  end
end

Setting = Struct.new(:x, :y, :resized_x, :resized_y, :angle)
rider_settings = {
  :decade => Setting.new(564, 171, Card::X-1, Card::Y, -2.5),

  :hibiki => Setting.new(402, 432, Card::X-18, Card::Y, 13.6),
  :kabuto => Setting.new(434, 440, Card::X-14, Card::Y, 13.6),
  :den_o =>  Setting.new(475, 447, Card::X-14, Card::Y, 13.4),
  :kiva =>   Setting.new(514, 454, Card::X-10, Card::Y, 13.4),

  :kuuga =>  Setting.new(567, 460, Card::X, Card::Y, 0),

  :agito =>  Setting.new(622, 448, Card::X, Card::Y, -12),
  :ryuki =>  Setting.new(676, 436, Card::X, Card::Y, -12),
  :faiz =>   Setting.new(737, 428, Card::X, Card::Y, -10.3),
  :blade =>  Setting.new(790, 419, Card::X, Card::Y, -10.3)
}

# http://subtech.g.hatena.ne.jp/secondlife/20061115/1163571997
def valid_http_uri?(str)
  URI.split(str).first == 'http' rescue false
end

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
    if valid_http_uri?(user)
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
  filter = %w(decade hibiki kabuto den_o kiva kuuga agito ryuki faiz blade)
  params.delete_if {|k, v| !filter.include?(k.to_s) }

  result = ImageList.new('images/decade.jpg')
  rider_settings.each do |k, v|
    result = Card.new(result).generate(params[k], v)
  end

  image = Photo.create(:body => b64encode(result.to_blob))
#  Photo.all(:created_at.lt => (Time.now - 60 * 60)).each do |photo|
#    photo.destroy
#  end

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
  @ids = []
  Photo.all(:order => [:id.desc]).each do |photo|
    @ids << photo.id
  end
  erb :list
end


# -*- coding: utf-8 -*-
require 'rubygems'
require 'sinatra'
require 'RMagick'
require 'hpricot'
require 'open-uri'
require 'lib/my_magick' # for RMagick 1.x

include Magick

RIDERS = %w(decade hibiki kabuto den_o kiva kuuga agito ryuki faiz blade)
CARD_X = 43.0
CARD_Y = 55.0

Card = Struct.new(:x, :y, :resized_x, :resized_y, :angle)
cards = {
  :decade => Card.new(564, 171, CARD_X-1, CARD_Y, -2.5),

  :hibiki => Card.new(402, 432, CARD_X-18, CARD_Y, 13.6),
  :kabuto => Card.new(434, 440, CARD_X-14, CARD_Y, 13.6),
  :den_o =>  Card.new(475, 447, CARD_X-14, CARD_Y, 13.4),
  :kiva =>   Card.new(514, 454, CARD_X-10, CARD_Y, 13.4),

  :kuuga =>  Card.new(567, 460, CARD_X, CARD_Y, 0),

  :agito =>  Card.new(622, 448, CARD_X, CARD_Y, -12),
  :ryuki =>  Card.new(676, 436, CARD_X, CARD_Y, -12),
  :faiz =>   Card.new(737, 428, CARD_X, CARD_Y, -10.3),
  :blade =>  Card.new(790, 419, CARD_X, CARD_Y, -10.3)
}

class Object
  def blank?
    respond_to?(:empty?) ? empty? : !self
  end
end

def decade
  ImageList.new('images/decade.jpg')
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
    begin
      twitter = Hpricot(open("http://twitter.com/#{user}"))
      image = (twitter/"img#profile-image").map{|e| e['src'] }.first
      if image.blank?
        image = (twitter/"img.profile-img").map{|e| e['src'] }.first
      end
      if image.blank?
        image = "images/twitter_bigger.png"
      end
    rescue
      image = "images/twitter_bigger.png"
    end
  end
  URI.encode(image)
end

def generate(result, user, opt)
  return result if user.blank?

  src = ImageList.new(image_src(user)).first
  src.background_color = "none"
  src.resize_to_fill!(CARD_X, CARD_Y).
    resize!(opt.resized_x, opt.resized_y).
    rotate!(opt.angle)
  result = result.composite(src, opt.x, opt.y, OverCompositeOp)
end

get '/' do
  erb :index
end

post '/' do
  params.delete_if {|k, v| !RIDERS.include?(k.to_s) }

  result = decade
  cards.each do |k, v|
    result = generate(result, params[k], v)
  end

  content_type :jpg
  return result.to_blob
end

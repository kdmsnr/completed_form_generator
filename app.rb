# -*- coding: utf-8 -*-
require 'rubygems'
require 'sinatra'
require 'RMagick'
require 'hpricot'
require 'open-uri'

include Magick

RIDERS = %w(decade hibiki kabuto denou kiva kuga agito ryuki fives blade)

Card = Struct.new(:x, :y, :resized_x, :resized_y, :angle)
cards = {
  :decade => Card.new(556, 163, 50, 74, -1.5),

  :hibiki => Card.new(391, 430, 33, 67, 14),
  :kabuto => Card.new(426, 440, 35, 67, 13),
  :denou => Card.new(465, 447, 35, 70, 13),
  :kiva =>   Card.new(503, 454, 43, 70, 13),

  :kuga =>   Card.new(560, 461, 50, 73, 0),

  :agito =>  Card.new(613, 448, 53, 72, -11),
  :ryuki =>  Card.new(669, 436, 51, 72, -12),
  :fives =>  Card.new(730, 426, 49, 71, -12),
  :blade =>  Card.new(782, 415, 50, 71, -13)
}

def decade
  ImageList.new('images/decade.jpg')
end

def generate(result, user, opt)
  return result if user.empty?

  begin
    case user
    when "akr"
      image_url = "images/akr.jpg"
    when "_why"
      image_url = "images/_why.jpg"
    when "_ko1"
      image_url = "images/_ko1.jpg"
    when "takahashim"
      image_url = "images/takahashim.jpg"
    when "yukihiro_matz"
      image_url = "images/matz.jpg"
    else
      twitter = Hpricot(open("http://twitter.com/#{user}"))
      image = (twitter/"img#profile-image").map{|e| e['src'] }
      if image.empty?
        image_url = "images/twitter_bigger.png"
      else
        image_url = image.first
      end
    end

    src = ImageList.new(URI.encode(image_url)) {
      self.background_color = "none"
    }
    src.resize_to_fill!(opt.resized_x, opt.resized_y).rotate!(opt.angle)
    result = result.composite(src, opt.x, opt.y, OverCompositeOp)
  rescue
    result
  end
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
  send_data result.to_blob
end

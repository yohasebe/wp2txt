#!/usr/bin/env ruby
# -*- coding: utf-8 -*-

$: << File.join(File.dirname(__FILE__))

require 'uri'
require 'net/http'
require 'json'
require 'utils'


module Wp2txt

  def post_request(uri_string, data={})
    data = data.map{ |k, v| "#{k}=#{v}" }.join("&")
    uri = URI.parse(uri_string)
    uri.path = "/" if uri.path.empty?
    http = Net::HTTP.new(uri.host)
    return http.post(uri.path, data).body
  end

  def expand_template(uri, template, page)
    text = URI.escape(template)
    title = URI.escape(page)
    data = {"action" => "expandtemplates",
            "format" => "json",
            "text"   => text,
            "title"  => title}
    jsn = post_request(uri, data)
    hash = JSON.parse(jsn)
    begin
      result = hash["expandtemplates"]["*"]
      result = special_chr(result)
      return chrref_to_utf(result).gsub("{{", "&#123;&#123;").gsub("}}", "&#125;&#125;")
    rescue => e      
      puts "ERROR!"
      p e
      exit
      template
    end
  end

  def parse_wikitext(uri, wikitext, page)
    text = URI.escape(wikitext)
    title = URI.escape(page)
    data = {"action" => "parse",
            "format" => "json",
            "text"   => text,
            "title"  => title}
    jsn = post_request(uri, data)
    hash = JSON.parse(jsn)
    begin
      result = hash["parse"]["text"]["*"]
      result = special_chr(result)
      return chrref_to_utf(result).gsub("[[", "&#91;&#91;").gsub("]]", "&#93;&#93;")
    rescue => e      
      puts "ERROR!"
      p e
      exit
      template
    end
  end
  
end
# 
# class Test
#   include Wp2txt
# end

#template = "{{quote-book|1503|year_published=1836|chapter=19 Henry VII. c. 5: Coin||A Collection of Statutes Connected with the General Administration of the Law|page=158|url=http://books.google.com/books?id=QtYuAAAAIAAJ
#|passage={{...}} every of them, being gold, whole and weight, shall '''go''' and be current in payment throughout this his realm for the sum that they were coined for.}}"
# word = "kick"
# template = "{{en-verb}}"
# p t = Test.new.expand_template(template, word)
#word = "go"
#template = "{{rfdef|lang=en}}"
#p t = Test.new.expand_template(template, word)

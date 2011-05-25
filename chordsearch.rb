require 'sinatra'
require 'mongo'
require 'haml'
require 'json'

set :app_file, __FILE__
enable :static

class GuitarChord
  def self.dummy
    new('chord' => 'A', 'modifier' => 'major', 'b' => '2', 'g' => '2', 'D' => '2')
  end

  def self.instrument
    'guitar'
  end

  def self.search_chord(query)
    new('data' => @query)
  end

  def self.modifiers
    [
      'major', 'minor', '7', 'm7', 'maj7', 'mmaj7', '6', 'm6', 'sus', 'dim', 'aug',
      '7sus4', '5', '-5', '7-5', '7maj5', 'm9', 'maj9', 'add9', '11', '13', '6add9'
    ]
  end

  attr_reader :chord, :modifier, :data

  def initialize(raw = {})
    @chord = raw['chord']
    @modifier = raw['modifier']
    @raw = raw
    @data = Hash[strings.map { |s| [s, raw[s] || '0'] }]
  end

  def strings
    ['E', 'A', 'D', 'g', 'b', 'e'].reverse
  end

  def url_html
    "http://chordsearch.heroku.com/guitar/#{key}"
  end

  def url_json
    "#{url_html}.json"
  end

  def key
    strings.map { |s| [s, data[s]] }.flatten.join <<
      '--' << name.gsub(/\s+/, '_')
  end

  def obscurity_score
    self.class.modifiers.index(modifier) || self.class.modifiers.length
  end

  def distance(other)
    data.inject(0) do |memo, string_fret|
      string, fret = string_fret
      memo + (other.data[string].to_i - fret.to_i).abs
    end
  end

  def search_key
    @raw.to_a.flatten.join
  end

  def self.search_path(q)
    path = new(q).search_key
    path == '' ? "/#{instrument}/#{path}" : path
  end

  def name
    [chord, modifier].join(' ')
  end

  def to_json(*args)
    {
      "instrument" => "guitar",
      "chord"      => chord,
      "modifier"   => modifier,
      "url_html"   => url_html,
      "url_json"   => url_json,
      "tones"      => data
    }.to_json
  end
end

module ChordDB
  def self.connect
    uri = URI.parse(ENV['MONGOHQ_URL'])
    conn = Mongo::Connection.from_uri(ENV['MONGOHQ_URL'])
    @db = conn.db(uri.path.gsub(/^\//, ''))
  end

  class << self
    def chord_class(instrument)
      {
        'guitar' => GuitarChord,
      }[instrument]
    end
    alias :[] :chord_class
  end

  def self.db
    @db ||= connect
  end

  def self.query_from_param(q)
    query = {} if q == 'all'
    query ||= Hash[
      q.to_s.split('--').first.scan(/([a-zA-Z])(\d+)/) # [['e', '5'], ['b', '6']]
    ] # {'e' => '5', 'b' => '6'}
  end

  def self.find_chords(query, instrument)
    chords = ENV['NOINTERNET'] ? [GuitarChord.dummy] :
      db[instrument].find(query).map do |result|
        chord_class(instrument).new(result)
      end
    search_chord = chord_class(instrument).search_chord(query)
    chords.sort_by do |chord|
      [chord.distance(search_chord), chord.obscurity_score]
    end
  end

  def self.insert(instrument, data)
    db[instrument].insert(data)
  end
end

get '/' do
  haml :index
end

get %r{^/(\w+)$} do |instrument|
  redirect "/#{instrument}/"
end

get %r{^/(\w+)/$} do |instrument|
  redirect '/' unless ChordDB[instrument]
  @query = {}
  @search_chord = ChordDB[instrument].new
  @chords = []
  haml :chords
end

get %r{^/(\w+)/(.*\.json)$} do |instrument, q|
  query = ChordDB.query_from_param(q)
  ChordDB.find_chords(query, instrument).to_json
end

get %r{^/(\w+)/(.*)$} do |instrument, q|
  @query = ChordDB.query_from_param(q)
  @search_chord = ChordDB[instrument].search_chord(@query)
  @chords = ChordDB.find_chords(@query, instrument)
  haml :chords
end

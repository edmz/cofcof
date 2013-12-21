require "mechanize"
require "sequel"
require "date"

#require "./config/environments"


# connect to an in-memory database
DB = Sequel.sqlite('./db/metrics.sqlite3')

# create an items table
if !DB.table_exists? :metrics
  DB.create_table :metrics do
    FixNum :station_id
    Date :day
    Fixnum :hour
    Float :pm10
    Float :ozone
    Float :co
    Float :so2
    Float :no2
    Float :pm25
    Float :wind_speed
    Float :temperature
    Float :relative_humidity
    Float :wind_direction
    Float :average_pressure
    Float :atmospheric_pressure
    Float :milimeters_of_rain
    Float :solar_radiation
    Fixnum :counter
    primary_key [:station_id, :day, :hour], name: "metrics_pk", auto_increment: false
  end  
end

class SimaParser
  
  AVAILABLE_STATION_IDS = [1, 2, 3, 4, 5, 6, 7, 8, 11]
  SIMA_WEBROOT          = "http://www.nl.gob.mx/?P=sima_metropolitano&url=SistemaGubernamentales/sima/ReporteDiarioDetallado.aspx"
  
  def initialize
    @agent = Mechanize.new
  end
  
  def parse_station(station_number)
    if page = get_page(station_number)
      return { 
        timestamp:  Time.now.to_i,
        station_id: station_number,
        station_name: page.search("#divUbicacion").children.first.to_s.strip,
        contaminants: get_data_in_hash(page, "#dgContaminantes  tr.itemStyle"),
        weather_data: get_data_in_hash(page, "#dgMeterologicos  tr.itemStyle")
      }      
    else
      return { }
    end
  end
  
  def get_page(station_number)
    page         = nil
    num_attempts = 0
    begin
      num_attempts += 1
      page          = @agent.get(station_url(station_number))            
    rescue StandardError
      retry if num_attempts <= 3
    end
    return page
  end
  
  def convert_label_to_symbol(label_str)
    case label_str
    when /PM10/             then :pm10
    when /Ozono/            then :ozone
    when /CO/               then :co
    when /SO2/              then :so2
    when /NO2/              then :no2
    when /PM2\.5/           then :pm25
    when /elocidad.*viento/ then :wind_speed
    when /emperatura/       then :temperature
    when /relativa/         then :relative_humidity
    when /proveniente/      then :wind_direction
    when /media/            then :average_pressure
    when /atmos/            then :atmospheric_pressure
    when /luvia/            then :milimeters_of_rain
    when /solar/            then :solar_radiation
    else label_str            
    end
  end
  
  def convert_string_to_usable_type(string_value)
    string_value.to_f
  end
  
  def get_data_in_hash(page, xpath_search)
    array_of_values = collect_table_values(page, xpath_search)
    array_of_values.inject({ }) do |memo, object|
      metric_name               = object[0]
      memo[metric_name]         = { value: convert_string_to_usable_type(object[1]) }
      memo[metric_name][:extra] = object[2] if object.count == 3
      memo
    end
  end
  
  def collect_table_values(page, xpath_search)
    page.search(xpath_search).collect do |table_row|
      table_row.children.select do |tag|
        "td" == tag.name
      end.collect do |td_tag|
        case td_tag.children.first
        when Nokogiri::XML::Element then convert_label_to_symbol(td_tag.children.first.children.first.to_s.strip)
        when Nokogiri::XML::Text    then td_tag.children.first.to_s.strip
        else nil
        end
      end      
    end           
  end
  
  def station_url(station_number)
    SIMA_WEBROOT + "&param1=St=%i" % [station_number]
  end
  
  def parse_available_stations
    AVAILABLE_STATION_IDS.inject(Hash.new) do |memo, station_id|
      memo[station_id] = parse_station(station_id)
      memo
    end
  end
  
end

def build_key_value_pairs_for_info(station_info)
  kvps = station_info[:contaminants].inject({ }) do |memo,object|
    memo[object[0]] = object[1][:value]
    memo
  end
  kvps = station_info[:weather_data].inject(kvps) do |memo,object|
    memo[object[0]] = object[1][:value]
    memo
  end
  kvps[:day]  = Time.now.day
  kvps[:hour] = Time.now.hour  
  kvps
end

metrics = items = DB[:metrics]
1.upto(100) do 
  SimaParser.new().parse_available_stations().each_pair do |station_id, station_info|  
    kvps = build_key_value_pairs_for_info(station_info)
    metrics.insert({ station_id: station_id}.merge(kvps))
  end
  
  puts Time.now
  sleep(60*60)
end





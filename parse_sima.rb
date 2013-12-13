require "mechanize"
class SimaParser
  
  AVAILABLE_STATION_IDS = [1, 2, 3, 4, 5, 6, 7, 8,   
  SIMA_WEBROOT          = "http://www.nl.gob.mx/?P=sima_metropolitano&url=SistemaGubernamentales/sima/ReporteDiarioDetallado.aspx"
  
  def initialize
    @agent = Mechanize.new
  end
  
  def parse_station(station_number)
    page             = @agent.get(station_url(station_number))        
    return { 
      timestamp:  Time.now.to_i,
      station_id: station_number,
      station_name: page.search("#divUbicacion").children.first.to_s.strip,
      contaminants: get_data_in_hash(page, "#dgContaminantes  tr.itemStyle"),
      weather_data: get_data_in_hash(page, "#dgMeterologicos  tr.itemStyle")
    }
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
    array_of_values.inject(Hash.new) do |memo, object|
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


1.upto(24) do
  p SimaParser.new().parse_available_stations()
  sleep(60*60)
end

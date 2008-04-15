require 'set'
class RailsLogStat
  
  class RequestStatistics
    attr_accessor :sql_stats         # {'Article' => [0.2, 0.42332...], 'Body' => [0.45, 0.5923...], ... }
    attr_accessor :rendered_stats    # {'/layout/application' => [0.2, 0.42332...], 'resources/edit' => [0.45, 0.5923...], ... }
    attr_accessor :completion_time, :rendering_time, :db_time
    attr_accessor :http_status, :url
    
    def initialize
      @sql_stats, @rendered_stats = Hash.new{ |hash,key| hash[key]=[] }, Hash.new{ |hash,key| hash[key]=[] }
    end
  end
  
  # Processing IndexController#index (for 127.0.0.1 at 2008-04-13 06:40:20) [GET]
  # $1 => 'ActionController#index', $2 => 'GET'
  REQUEST_BEGIN_MATCHER = /Processing\s+(\S+Controller#\S+) \(for.+\) \[(GET|POST)\]$/  
  
  
  # ModelClassName Load (0.000292)SELECT * FROM `answers` WHERE `id` = 2000
  # $1 => ModelClassName, $2 => 0.0453 
  SQL_LOAD_MATCHER = /([A-Z]\S+)\s+Load.+\((\d+\.\d+)\).+SELECT/
  
  # Rendered layout/application (0.00995)
  # $1 => layout/application, $2 => 0.00995
  RENDERED_MATCHER = /^Rendered (\S+) \((\d+\.\d+)\)$/
  
  # Completed in 3.48602 (0 reqs/sec) | Rendering: 1.53868 (44%) | DB: 0.79623 (22%) | 200 OK [http://www.example.com]
  # $1 => 3.48602, $2 => 1.53868, $3 => 44, $4 => 0.79623, $5 => 22, $6 => 200 OK, $7 => http://www.example.com
  REQUEST_COMPLETION_MATCHER = /^Completed in (\d+\.\d+).+Rendering: (\d+\.\d+) \((\d+)%\).+DB: (\d+\.\d+) \((\d+)%\) \| ([1-5]\d{2} \S+) \[(.+)\]$/
    
  attr_accessor :log_file_path, :max_stats_per_request

  def initialize log_file_path, max_stats_per_request=25
    # sample @request hash
    # { 
    #   'Article#index[POST]' => [ request_statistics_1, request_statistics_2, ..],
    #   'Article#index[GET]' => [ request_statistics_1, request_statistics_2, ..],
    #   ...
    # }
    @requests = Hash.new{ |hash,key| hash[key]=[] }
    @current_request = nil
    @log_file_path, @max_stats_per_request = log_file_path, max_stats_per_request
  end
  
  def parse_log_file command="tail -f"
    @log_thread ||= Thread.new do
      pipe = IO.popen "#{command.strip} #{log_file_path}", 'r'  # new pipe for tailing a text file
      while message_line = pipe.gets
        parse_line message_line
      end
    end
  end
  
  # Pattern match each line w/ Regexp
  def parse_line line
    if match = line.match( REQUEST_BEGIN_MATCHER )  
      request, method  = match[1], match[2]
      @current_request = "#{request} [#{method}]"   # => "ActionController#index [GET]"
      @current_request_stats = (@requests[@current_request] << RequestStatistics.new).last # newest request stats is the one that just pushed into the buffer
      @requests[@current_request].unshift if @requests[@current_request].size > @max_stats_per_request  # pop out oldest request stats if buffer is full
    elsif match = line.match( SQL_LOAD_MATCHER )
      if @current_request # guard against old queries that doesn't have leading request log
        model_name, timing = match[1], match[2].to_f
        @current_request_stats.sql_stats[model_name] << timing
      end
    elsif match = line.match( RENDERED_MATCHER )
      rendered_file_name, timing = match[1], match[2].to_f
      @current_request_stats.rendered_stats[rendered_file_name] << timing
    elsif match = line.match( REQUEST_COMPLETION_MATCHER )
      if @current_request
        @current_request_stats.completion_time = match[0].to_f
        @current_request_stats.rendering_time  = match[2].to_f
        @current_request_stats.db_time         = match[4].to_f
        @current_request_stats.http_status     = match[6]
        @current_request_stats.url             = match[7]
      end
    end
  end
  
  # Array of [ avg. # loads per request,   avg. time per request, model class name ]
  # notes average over the union might not be a good enough metrics, b/c some request might contain very little or no loads info for a specific model
  # it's generally a good idea to control your inputs for a specific log, so results are resonably consistent to compare with
  def sql_averges_for_request request
    averages_for_request request, :sql_stats
  end
  
  def rendered_averages_for_request request
    averages_for_request request, :rendered_stats
  end
  
  def averages_for_request request, stat_type
    unless (num_of_requests = @requests[request].size) == 0
      # union of all stat names
      stat_names = @requests[request].inject(Set.new){ |stat_names, request_stats| stat_names |= Set.new(request_stats.send(stat_type).keys) }.to_a
      timing_sums = Hash.new{ |hash,key| hash[key]=0.0 }
      count_sums = Hash.new{ |hash,key| hash[key]=0 }
      
      @requests[request].each do |request_stats|
        stat_names.each do |stat_name|
          # note, this can modify request_stats's keys since we have default hashes
          timing_sums[stat_name] += request_stats.send(stat_type)[stat_name].inject(0.0){|sum, t| sum += t } 
          count_sums[stat_name]  += request_stats.send(stat_type)[stat_name].size
        end
      end
      
      num_of_requests = num_of_requests.to_f
      stat_names.collect do |stat_name|
        [ count_sums[stat_name] / num_of_requests, timing_sums[stat_name] / num_of_requests, stat_name ]
      end
    else
      []
    end
  end
  
  def request_names
    @requests.keys.sort
  end
  
  def request_count request
    @requests[request].size
  end
    
end


if __FILE__ == $0
  exit if PLATFORM =~ /win32/
  exit unless STDOUT.tty?
  unless ARGV[0]
    puts 'You need to specify the path to the log file'
    exit
  end
  
  log_stat = RailsLogStat.new ARGV[0]
  log_stat.parse_log_file ARGV[1] || 'tail -f'
  
  header_spacing = "\t"
  spacing = "\t" * 3
  headers = 'QUERIES / REQUEST' + header_spacing + 'TOTAL TIME SPENT / REQUEST' + header_spacing + 'MODEL NAME'
  
  loop do 
    puts "\n"
    puts "Usage: 'r' to list requests; type 'request name' for stats..."
    if (input = STDIN.gets.strip) == 'r'
      log_stat.request_names.each { |request_name| puts "--->  #{request_name}" }
    elsif input == 'q'
      puts 'Bye!'
      exit
    else
      if log_stat.request_names.include? input
        puts "#{'='*80}"
        puts "#{input}: #{log_stat.request_count input} calls."
        puts "#{'='*80}"
        puts headers
        puts '-' * 80
        stats = log_stat.sql_averges_for_request(input)
        stats.sort!{ |stat1, stat2| stat2[1] <=> stat1[1] }
        stats.each do |stat|
          total_time_spent_per_request  = ('%.2f' % stat[0] )
          total_loads_per_request  = ('%.6f' % stat[1] )
          puts total_time_spent_per_request + spacing + total_loads_per_request + spacing + stat[2].to_s
        end
        puts "#{'='*80}"
      else
        puts 'ERROR: request not found...'
      end
    end
  end
end
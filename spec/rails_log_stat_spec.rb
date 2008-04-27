require File.dirname(__FILE__) + '/../spec_helpers/spec_helper'
require 'rails_log_stat'

describe RailsLogStat, "Matchers" do
  include LogLineMatchers
  
  it 'should match initial request line' do
    'Processing IndexController#destroy (for 127.0.0.1 at 2008-04-13 06:43:02) [DELETE]'.should extract_begin_request_properties( :controller_action => 'IndexController#destroy',  :http_method => 'DELETE' )
    'Processing ClientsController#update (for 127.0.0.1 at 2008-04-13 06:43:02) [PUT]'.should   extract_begin_request_properties( :controller_action => 'ClientsController#update', :http_method => 'PUT' )
    'Processing PagesController#create (for 127.0.0.1 at 2008-04-13 06:43:02) [POST]'.should    extract_begin_request_properties( :controller_action => 'PagesController#create',   :http_method => 'POST' )
    'Processing DraftsController#edit (for 127.0.0.1 at 2008-04-13 06:43:02) [GET]'.should      extract_begin_request_properties( :controller_action => 'DraftsController#edit',    :http_method => 'GET' )
  end
  
  it 'should match sql line' do
    "Game Update (0.000221)  UPDATE `users` SET `score` = 90 WHERE `id` = 2000".should extract_sql_properties( :model_name => 'Game',    :ar_op => 'Update',  :time => '0.000221', :sql_op => 'UPDATE')
    "User Create (0.002000)  INSERT INTO `users` (`name`) VALUES('funny_guy')".should  extract_sql_properties( :model_name => 'User',    :ar_op => 'Create',  :time => '0.002000', :sql_op => 'INSERT')
    "Article Destroy (0.002000) DELETE FROM `atricles` WHERE `id` = 2000".should      extract_sql_properties( :model_name => 'Article', :ar_op => 'Destroy', :time => '0.002000', :sql_op => 'DELETE')
    "Answer Load (1.092000) SELECT * FROM `answers` WHERE `id` = 2000".should         extract_sql_properties( :model_name => 'Answer',  :ar_op => 'Load',    :time => '1.092000', :sql_op => 'SELECT')
  end
  
  it 'should match rendered partial line' do
    'Rendered /layouts/admin/_notice (0.00132)'.should extract_rendered_partial_properties( :template => '/layouts/admin/_notice', :render_time => '0.00132')
  end
  
  it 'should match request completion line' do
    'Completed in 3.48602 (0 reqs/sec) | Rendering: 1.53868 (44%) | DB: 0.79623 (22%) | 200 OK [http://www.example.com]'.should 
        extract_request_completion_properties( :completion_time => '3.48602', :render_time => '1.53868', :render_percent => '44', 
                                               :db_time => '0.79623', :db_percent => '22', :http_status => '200 OK', :url => 'http://www.example.com' )
  end
end


describe RailsLogStat, "single request statistics" do
  before(:each) do
    @log_stat = RailsLogStat.new 'file.log', 3
    @request_name = "UsersController#index [GET]"
    @log_stat.parse_line "Processing UsersController#index (for 127.0.0.1 at 2008-04-13 06:43:02) [GET]"
  end
  
  it 'should have correct average total database time per request with only one Model / SQL type' do
    load_times = [ 3.001, 2.5, 2.0023 ]
    load_times.each { |load_time| @log_stat.parse_line "User Load (#{load_time}) SELECT * FROM users" }
    averages = @log_stat.averages_for_request( @request_name, :sql_stats )
    
    averages.size.should == 1
    sql_count, load_time_average = averages.first
    load_times.size.should == sql_count
    load_times.sum.should == load_time_average
  end
  
  it "should have correct average total database time per request with multiple Model / SQL types" do
    load_times = [ 3.001, 2.5, 2.0023 ]
    update_times = [ 0.0021, 0.00025, 0.0023 ]
    
    # mix up load & update queries
    load_times.each_with_index do |load_time, i| 
      @log_stat.parse_line "User Load (#{load_time}) SELECT * FROM users" 
      @log_stat.parse_line "User Update (#{update_times[i]}) UPDATE users set viewed = 1 where id = #{i}"
    end

    averages = @log_stat.averages_for_request( @request_name, :sql_stats )
    averages.size.should == 2

    sql_load_count, load_time_average = averages.detect{ |avg| avg.last =~ /Load/ }
    load_times.size.should == sql_load_count
    load_times.sum.should == load_time_average
    
    sql_update_count, update_time_average = averages.detect{ |avg| avg.last =~ /Update/ }
    update_times.size.should == sql_update_count
    update_times.sum.should == update_time_average
  end
    
end


describe RailsLogStat, "multiple requests statistics" do
  it "should have correct statistics for multiple requests"
  it "should clear oldest statistics when buffer has gone over its maximum size"
  it "should have correct sql time averages when buffer is recycled"
end
require File.dirname(__FILE__) + '/../spec_helpers/spec_helper'
require 'rails_log_stat'

describe RailsLogStat, "Matchers" do
  include LogLineMatchers
  it 'should match initial request line' do
    'Processing IndexController#destroy (for 127.0.0.1 at 2008-04-13 06:43:02) [DELETE]'.should extract_controller_action_and_http_method( 'IndexController#destroy', 'DELETE' )
    'Processing ClientsController#update (for 127.0.0.1 at 2008-04-13 06:43:02) [PUT]'.should   extract_controller_action_and_http_method( 'ClientsController#update', 'PUT' )
    'Processing PagesController#create (for 127.0.0.1 at 2008-04-13 06:43:02) [POST]'.should    extract_controller_action_and_http_method( 'PagesController#create', 'POST' )
    'Processing DraftsController#edit (for 127.0.0.1 at 2008-04-13 06:43:02) [GET]'.should      extract_controller_action_and_http_method( 'DraftsController#edit', 'GET' )
  end
  
  it 'should match sql line' do
    "Game Update (0.000221)  UPDATE `users` SET `score` = 90 WHERE `id` = 2000".should extract_model_name_and_ar_op_and_time_and_sql_op( 'Game', 'Update', '0.000221', 'UPDATE')
    "User Create (0.002000)  INSERT INTO `users` (`name`) VALUES('funny_guy')".should  extract_model_name_and_ar_op_and_time_and_sql_op( 'User', 'Create', '0.002000', 'INSERT')
    "Article Destroy (0.002000) DELETE FROM `atricles` WHERE `id` = 2000".should      extract_model_name_and_ar_op_and_time_and_sql_op( 'Article', 'Destroy', '0.002000', 'DELETE')
    "Answer Load (1.092000) SELECT * FROM `answers` WHERE `id` = 2000".should         extract_model_name_and_ar_op_and_time_and_sql_op( 'Answer', 'Load', '1.092000', 'SELECT')
  end
  
  it 'should match rendered partial line' do
    'Rendered /layouts/admin/_notice (0.00132)'.should extract_template_and_render_time( '/layouts/admin/_notice', '0.00132')
  end
end
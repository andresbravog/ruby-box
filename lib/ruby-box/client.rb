require 'uri'
require 'net/https'
require 'json'
require 'net/http/post/multipart'
require 'open-uri'

module RubyBox
  class Client

    def initialize(session)
      @session = session
    end

    def root_folder
      folder_by_id('0')
    end

    def folder_by_id(id)
      folder = Folder.new(@session, {'id' => id})
      folder.reload_meta
    end

    def folder(path='/')
      path = path.sub(/(^\.$)|(^\.\/)/, '') if path # handle folders with leading '.'
      return root_folder if ['', '/'].member?(path)
      folder_from_split_path( split_path(path) )
    end

    def file_by_id(id)
      file = File.new(@session, {'id' => id})
      file.reload_meta
    end

    def file(path)
      path = split_path( path.sub(/^\.\//, '') )
      file_name = path.pop
      folder = folder_from_split_path( path )
      folder.files(file_name).first if folder
    end

    def item(path)
      path = split_path( path.sub(/^\.\//, '') )
      item_name = path.pop
      folder = folder_from_split_path( path )

      folder.items.select do |item|
        item.instance_variable_get(:@raw_item)['name'] and item.name == item_name
      end.first
    end

    def download(path)
      file = file(path)
      file.download if file
    end

    def stream(path, opts={})
      file = file(path)
      file.stream(opts) if file
    end

    # Searchs in box API by the given options
    #
    # @param query [String] query to search for
    # @param options [Hash] options given to the API box search endpoint
    # @option options [Integer] item_limit (100) limit of the batch fo search
    # @option options [Integer] offset (0) offset for the search
    # @option options [String] scope () scope to search items ['user_content', 'enterprise_content', 'enterprise_content']
    # @option options [Array<String>] file_extensions () extension of files to serch for ['jpg', 'png', ...]
    # @option options [Array<String>] content_types () type of the content to search in ['name', 'description', 'file_content', 'comments', 'tags']
    # @option options [ArrayzString>] type () type of the items to search for ['folder', 'file', 'web_link']
    # @return [Array<RubyBox::Item>]
    def search(query, options={})
      options[:item_limit] ||= 100
      options[:offset] ||= 0
      Enumerator.new do |yielder|
        while true
          url  = "#{RubyBox::API_URL}/search?query=#{URI::encode(query)}"
          url += "&limit=#{options[:item_limit]}"
          url += "&offset=#{options[:offset]}"
          url += "&scope=#{options[:scope]}" if options[:scope]
          url += "&file_extensions=#{options[:file_extensions].join(',')}" if options[:file_extensions]
          url += "&content_types=#{options[:content_types].join(',')}" if options[:content_type]
          url += "&type=#{options[:type].join(',')}" if options[:type]
          resp = @session.get( url )
          resp['entries'].each do |entry|
            yielder.yield(RubyBox::Item.factory(@session, entry))
          end
          options[:offset] += resp['entries'].count
          break if resp['offset'].to_i + resp['limit'].to_i >= resp['total_count'].to_i
        end
      end
    end

    def create_folder(path)
      folder = root_folder
      folder_names = split_path(path)
      folder_names.each do |folder_name|
        new_folder = folder.folders(folder_name).first        
        if !new_folder
          begin
            new_folder = folder.create_subfolder(folder_name)
          rescue RubyBox::ItemNameInUse => e
            new_folder = folder.folders(folder_name).first
          end
        end
        folder = new_folder
      end
      folder
    end

    def upload_data(path, data, overwrite=true)
      path = split_path(path)
      file_name = path.pop
      folder = create_folder(path.join('/'))
      folder.upload_file(file_name, data, overwrite) if folder
    end

    def upload_file(local_path, remote_path, overwrite=true)
      folder = create_folder( remote_path )
      upload_file_to_folder(local_path, folder, overwrite)
    end

    def upload_file_by_folder_id(local_path, folder_id, overwrite=true)
      folder = folder_by_id(folder_id)
      upload_file_to_folder(local_path, folder, overwrite)
    end

    def split_path(path)
      path.gsub!(/(^\/)|(\/$)/, '')
      path.split('/')
    end

    def event_response(stream_position=0, stream_type=:all, limit=100)
      q = fmt_events_args stream_position, stream_type, limit
      url = "#{RubyBox::API_URL}/events?#{q}"
      resp = @session.get( url )
      EventResponse.new(@session, resp)
    end

    # Current user information
    #
    # @params query_params [Hash] query_params to add to the request
    # @option query_params [String] fields () fields to show in the request sparated by commas
    # @return [RubyBox::User]
    def me(query_params={})
      url = url_with_query_params("#{RubyBox::API_URL}/users/me", query_params)
      resp = @session.get(url)
      User.new(@session, resp)
    end

    # Enterprise users collection
    #
    # @params query_params [Hash] query_params to add to the request
    # @option query_params [String] filter_term ('') A string used to filter the results to only users starting with the filter_term in either the name or the login
    # @option query_params [Integer] limit (100) The number of records to return. (max=1000)
    # @option query_params [Integer] offset (0) The record at which to start
    # @return [Array(RubyBox::User)]
    def users(query_params={})
      query_params = query_params_with_default(query_params,  { filter_term: '', limit: 100, offset: 0 })
      url = url_with_query_params("#{RubyBox::API_URL}/users", query_params)
      resp = @session.get(url)
      resp['entries'].map do |entry|
        RubyBox::Item.factory(@session, entry)
      end
    end

    private

    # Joins given base url with the given params
    #
    # @params base_url [String] base url to join
    # @params query_params [Hash] given query params to join with the base url
    # @return [String]
    def url_with_query_params(base_url, query_params={})
      uri = URI.parse(base_url)
      new_query_params = URI.decode_www_form(uri.query || '') + query_params.to_a
      uri.query = URI.encode_www_form(new_query_params)
      uri.to_s
    end

    # Joins params with given default options
    #
    # @params query_params [Hash] given query params
    # @params default_options [Hash] default query params values if any of them are not given
    # @return [Hash]
    def query_params_with_default(query_params={}, default_options={})
      default_options.merge(query_params)
    end

    def upload_file_to_folder(local_path, folder, overwrite)
      file_name = local_path.split('/').pop
      return unless folder
      ::File.open(local_path, 'rb') do |data|
        folder.upload_file(file_name, data, overwrite)
      end
    end

    def folder_from_split_path(path)
      folder = root_folder
      path.each do |folder_name|
        folder = folder.folders(folder_name).first
        return nil unless folder
      end
      folder
    end

    def fmt_events_args(stream_position, stream_type, limit)
      unless stream_position.to_s == 'now'
        stream_position = stream_position.kind_of?(Numeric) ? stream_position : 0
      end
      stream_type = [:all, :changes, :sync, :admin_logs].include?(stream_type) ? stream_type : :all
      limit = limit.kind_of?(Fixnum) ? limit : 100
      "stream_position=#{stream_position}&stream_type=#{stream_type}&limit=#{limit}"
    end
    
  end
end

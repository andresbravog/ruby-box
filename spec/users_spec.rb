#encoding: UTF-8

require 'ruby-box'
require 'webmock/rspec'

describe '/users' do
  subject { @client.users }
  let(:user) { subject.first }

  before do
    @session = RubyBox::Session.new
    @client  = RubyBox::Client.new(@session)
    @users_json = File.read 'spec/fixtures/users.json'
    @users = JSON.load(@users_json)
    stub_request(:get, /#{RubyBox::API_URL}\/users/).to_return(body: @users_json, :status => 200)
  end

  it 'should return a list of all users in the enterprise' do
    subject.should be_a Array
  end

  it 'should return a list of all users in the enterprise as a user object' do
    user.should be_a RubyBox::User
  end

  it 'calls users endpoint with default query params' do
    subject
    assert_requested :get, "#{RubyBox::API_URL}/users?filter_term=&limit=100&offset=0"
  end

  context 'with filter_term param given' do
    subject { @client.users(filter_term: 'foo') }

    it 'overwrites the default value' do
      subject
      assert_requested :get, "#{RubyBox::API_URL}/users?filter_term=foo&limit=100&offset=0"
    end
  end

  context 'with limit and offset params given' do
    subject { @client.users(limit: 500, offset: 100) }

    it 'overwrites the default values' do
      subject
      assert_requested :get, "#{RubyBox::API_URL}/users?filter_term=&limit=500&offset=100"
    end
  end

  context 'with fields query param given' do
    let(:users_with_role_json) do
      hash = JSON.parse(@users_json)
      array = hash['entries']
      array.collect! do |user_hash|
        user_hash['role'] = 'coadmin'
        user_hash
      end
      hash['entries'] = array
      hash.to_json
    end
    let(:user) { subject.first }

    before do
      stub_request(:get, /#{RubyBox::API_URL}\/users\?fields=role/).to_return(body: users_with_role_json,
                                                                              :status => 200)
    end
    subject { @client.users(fields: 'role') }

    it { should be_a Array }
    it { user.should be_a RubyBox::User }
    it { user.role.should eql 'coadmin' }
  end
end

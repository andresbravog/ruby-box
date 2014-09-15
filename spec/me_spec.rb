#encoding: UTF-8

require 'ruby-box'
require 'webmock/rspec'

describe '/users/me' do
  before do
    @session = RubyBox::Session.new
    @client  = RubyBox::Client.new(@session)
    @me_json  = File.read 'spec/fixtures/me.json'
    @me = JSON.load @me_json
    stub_request(:get, /#{RubyBox::API_URL}\/users\/me/).to_return(body: @me_json, :status => 200)
  end

  it 'should return the currently logged in User' do
    me = @client.me
    me.instance_of?(RubyBox::User).should be_true
  end

  context 'with fields query param given' do
    let(:me_with_role_json) do
      hash = JSON.parse(@me_json)
      hash['role'] = 'coadmin'
      hash.to_json
    end

    before do
      stub_request(:get, /#{RubyBox::API_URL}\/users\/me\?fields=role/).to_return(body: me_with_role_json,
                                                                                  :status => 200)
    end
    subject { @client.me(fields: 'role') }

    it { should be_a RubyBox::User }
    its(:role) { should eq 'coadmin' }
  end
end

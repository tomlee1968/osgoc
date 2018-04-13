require 'spec_helper'
describe 'hiera' do

  context 'with defaults for all parameters' do
    it { should contain_class('hiera') }
  end
end

require 'spec_helper'
describe 'osgops' do

  context 'with defaults for all parameters' do
    it { should contain_class('osgops') }
  end
end

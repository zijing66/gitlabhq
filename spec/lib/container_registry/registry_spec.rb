# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ContainerRegistry::Registry do
  let(:path) { nil }
  let(:registry) { described_class.new('http://example.com', path: path) }

  subject { registry }

  it { is_expected.to respond_to(:client) }
  it { is_expected.to respond_to(:uri) }
  it { is_expected.to respond_to(:path) }

  it { expect(subject).not_to be_nil }

  describe '#path' do
    subject { registry.path }

    context 'path from URL' do
      it { is_expected.to eq('example.com') }
    end

    context 'custom path' do
      let(:path) { 'registry.example.com' }

      it { is_expected.to eq(path) }
    end
  end

  describe '#gitlab_api_client' do
    subject { registry.gitlab_api_client }

    it { is_expected.to be_instance_of(ContainerRegistry::GitlabApiClient) }
  end
end

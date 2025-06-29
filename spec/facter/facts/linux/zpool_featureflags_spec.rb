# frozen_string_literal: true

describe Facts::Linux::ZpoolFeatureflags do
  describe '#call_the_resolver' do
    subject(:fact) { Facts::Linux::ZpoolFeatureflags.new }

    let(:zpool_feature_flags) { 'async_destroy,empty_bpobj,lz4_compress,multi_vdev_crash_dump,spacemap_histogram' }

    before do
      allow(Facter::Resolvers::Zpool).to \
        receive(:resolve).with(:zpool_featureflags).and_return(zpool_feature_flags)
    end

    it 'returns the zpool_featureflags fact' do
      expect(fact.call_the_resolver).to be_an_instance_of(Facter::ResolvedFact).and \
        have_attributes(name: 'zpool_featureflags', value: zpool_feature_flags)
    end
  end
end

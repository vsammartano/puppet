require 'spec_helper'

# stub the selinux module for tests in travis
module Selinux
  def selinux_file_context_local_path
    'spec_dummy'
  end
end

semanage_provider = Puppet::Type.type(:selinux_fcontext).provider(:semanage)
fcontext = Puppet::Type.type(:selinux_fcontext)

fcontexts_local = <<-EOS
# This file is auto-generated by libsemanage
# Do not edit directly.

/foobar    system_u:object_r:bin_t:s0
/tmp/foobar -d system_u:object_r:boot_t:s0
/something/else -s <<none>>
EOS

describe semanage_provider do
  on_supported_os.each do |os, facts|
    context "on #{os}" do
      let(:facts) do
        facts
      end

      context "with a single #{name} fcontext" do
        before do
          Selinux.expects(:selinux_file_context_local_path).returns('spec_dummy')
          File.expects(:exist?).with('spec_dummy').returns(true)
          File.expects(:readlines).with('spec_dummy').returns(fcontexts_local.split("\n"))
        end
        it 'returns three resources' do
          expect(described_class.instances.size).to eq(3)
        end
        it 'regular contexts get parsed properly' do
          expect(described_class.instances[0].instance_variable_get('@property_hash')).to eq(
            ensure: :present,
            name: '/foobar_a',
            pathspec: '/foobar',
            file_type: 'a',
            seltype: 'bin_t',
            selrole: 'object_r',
            seluser: 'system_u',
            selrange: 's0'
          )
        end
        it '<<none>> contexts get parsed properly' do
          expect(described_class.instances[2].instance_variable_get('@property_hash')).to eq(
            ensure: :present,
            name: '/something/else_s',
            pathspec: '/something/else',
            file_type: 's',
            seltype: '<<none>>',
            selrole: nil,
            seluser: nil,
            selrange: nil
          )
        end
      end
      context 'with no fcontexts defined, and no fcontexts.local file' do
        before do
          Selinux.expects(:selinux_file_context_local_path).returns('spec_dummy')
          File.expects(:exist?).with('spec_dummy').returns(false)
        end
        it 'returns no resources' do
          expect(described_class.instances.size).to eq(0)
        end
      end
      context 'Creating with just seltype defined' do
        let(:resource) do
          res = fcontext.new(name: '/something(/.*)_a', file_type: 'a', seltype: 'some_type_t', ensure: :present, pathspec: '/something(/.*)')
          res.provider = semanage_provider.new
          res
        end

        it 'runs semanage fcontext -a ' do
          described_class.expects(:semanage).with('fcontext', '-a', '-t', 'some_type_t', '-f', 'a', '/something(/.*)')
          resource.provider.create
        end
      end
      context 'Deleting with just seltype defined' do
        let(:provider) do
          semanage_provider.new(name: '/something(/.*)_a', file_type: 'a', seltype: 'some_type_t', ensure: :present, pathspec: '/something(/.*)')
        end

        it 'runs semanage fcontext -d ' do
          described_class.expects(:semanage).with('fcontext', '-d', '-t', 'some_type_t', '-f', 'a', '/something(/.*)')
          provider.destroy
        end
      end
      context 'With resources differing from the catalog' do
        let(:resources) do
          return { '/var/lib/mydir_s' => fcontext.new(
            name: '/var/lib/mydir_s',
            pathspec: '/var/lib/mydir',
            file_type: 's',
            seltype: 'some_type_t'
          ),
                   '/foobar_a' => fcontext.new(
                     name: '/foobar_a',
                     file_type: 'a',
                     pathspec: '/foobar',
                     seltype: 'mytype_t',
                     seluser: 'myuser_u'
                   ) }
        end

        before do
          # prefetch should find the provider parsed from this:
          Selinux.expects(:selinux_file_context_local_path).returns('spec_dummy')
          File.expects(:exist?).with('spec_dummy').returns(true)
          File.expects(:readlines).with('spec_dummy').returns(fcontexts_local.split("\n"))
          semanage_provider.prefetch(resources)
        end
        it 'finds provider for /foobar' do
          p = resources['/foobar_a'].provider
          expect(p).not_to eq(nil)
        end
        context 'has the correct attributes' do
          let(:p) { resources['/foobar_a'].provider }

          it { expect(p.name).to eq('/foobar_a') }
          it { expect(p.file_type).to eq('a') }
          it { expect(p.seltype).to eq('bin_t') }
          it { expect(p.selrole).to eq('object_r') }
          it { expect(p.seluser).to eq('system_u') }
        end
        it 'can change seltype' do
          p = resources['/foobar_a'].provider
          described_class.expects(:semanage).with('fcontext', '-m', '-t', 'new_type_t', '-f', 'a', '/foobar')
          p.seltype = 'new_type_t'
        end
        it 'can change seluser' do
          p = resources['/foobar_a'].provider
          described_class.expects(:semanage).with('fcontext', '-m', '-s', 'unconfined_u', '-t', 'bin_t', '-f', 'a', '/foobar')
          p.seluser = 'unconfined_u'
        end
      end
    end
  end
end

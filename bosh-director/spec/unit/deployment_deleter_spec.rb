require 'spec_helper'

module Bosh::Director
  describe DeploymentDeleter do
    subject(:deleter) { described_class.new(Config.event_log, logger, dns_manager, 3, dns_enabled) }
    before do
      allow(Config).to receive(:cloud).and_return(cloud)
      allow(App).to receive_message_chain(:instance, :blobstores, :blobstore).and_return(blobstore)
    end
    let(:cloud) { instance_double(Bosh::Cloud) }
    let(:blobstore) { instance_double(Bosh::Blobstore::Client) }
    let(:instance_deleter) { instance_double(InstanceDeleter) }
    let(:vm_deleter) { instance_double(VmDeleter) }
    let(:dns_manager) { instance_double(DnsManager) }
    let(:dns_enabled) { false }

    describe '#delete' do
      let!(:deployment_plan) do
        instance_double(
          DeploymentPlan::Planner,
          name: 'fake-deployment',
          existing_instances: [
            Models::Instance.make,
            Models::Instance.make,
          ],
          model: deployment_model,
          skip_drain_for_job?: false
        )
      end
      let!(:deployment_model) { Models::Deployment.make }
      let!(:orphaned_vm) do
        vm = Models::Vm.make
        vm.instance = nil
        vm
      end
      let!(:deployment_stemcell) { Models::Stemcell.make }
      let!(:deployment_release_version) { Models::ReleaseVersion.make }
      before do
        deployment_model.add_vm(orphaned_vm)
        deployment_model.add_stemcell(deployment_stemcell)
        deployment_model.add_release_version(deployment_release_version)
        deployment_model.add_property(Models::DeploymentProperty.make)

        allow(instance_deleter).to receive(:delete_instances)
        allow(vm_deleter).to receive(:delete_vm).with(orphaned_vm)
        allow(deployment_model).to receive(:destroy)
      end

      it 'deletes deployment instances' do
        expect(instance_deleter).to receive(:delete_instances) do |instances, stage, options|
          expect(instances.map(&:model)).to eq(deployment_plan.existing_instances)
          expect(stage).to be_instance_of(EventLog::Stage)
          expect(options).to eq(max_threads: 3)
        end

        deleter.delete(deployment_plan, instance_deleter, vm_deleter)
      end

      it 'deletes vms without instances' do
        expect(vm_deleter).to receive(:delete_vm).with(orphaned_vm)
        deleter.delete(deployment_plan, instance_deleter, vm_deleter)
      end

      it 'removes all stemcells' do
        expect(deployment_stemcell.deployments).to include(deployment_model)
        deleter.delete(deployment_plan, instance_deleter, vm_deleter)
        expect(deployment_stemcell.reload.deployments).to be_empty
      end

      it 'removes all releases' do
        expect(deployment_release_version.deployments).to include(deployment_model)
        deleter.delete(deployment_plan, instance_deleter, vm_deleter)
        expect(deployment_release_version.reload.deployments).to be_empty
      end

      it 'deletes all properties' do
        deleter.delete(deployment_plan, instance_deleter, vm_deleter)
        expect(Models::DeploymentProperty.all.size).to eq(0)
      end

      context 'when dns is enabled' do
        let(:dns_enabled) { true }

        it 'deletes dns' do
          expect(dns_manager).to receive(:delete_dns_for_deployment).with('fake-deployment')
          deleter.delete(deployment_plan, instance_deleter, vm_deleter)
        end
      end

      context 'when dns is not enabled' do
        let(:dns_enabled) { false }

        it 'deletes dns' do
          expect(dns_manager).to_not receive(:delete_dns_for_deployment)
          deleter.delete(deployment_plan, instance_deleter, vm_deleter)
        end
      end

      it 'destroys deployment model' do
        expect(deployment_model).to receive(:destroy)
        deleter.delete(deployment_plan, instance_deleter, vm_deleter)
      end
    end
  end
end

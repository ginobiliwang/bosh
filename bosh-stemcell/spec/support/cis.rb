require 'set'

$cis_test_cases = Set.new

RSpec.configure do |config|
  config.before(:each) do |example|
    if example.full_description.include? "CIS-"
      $cis_test_cases += example.full_description.scan /CIS-(?:\d+\.?)+/
    end
  end

  config.register_ordering(:global) do |list|
    # make sure that cis test case check will be run at last
    list.each do |example_group|
      if example_group.metadata[:cis_check]
        list.delete example_group
        list.push example_group
        break
      end
    end

    list
  end
end
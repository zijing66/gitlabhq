# frozen_string_literal: true

RSpec.shared_examples 'a package detail' do
  it_behaves_like 'a working graphql query' do
    it_behaves_like 'matching the package details schema'
  end

  context 'with pipelines' do
    let_it_be(:build_info1) { create(:package_build_info, :with_pipeline, package: package) }
    let_it_be(:build_info2) { create(:package_build_info, :with_pipeline, package: package) }
    let_it_be(:build_info3) { create(:package_build_info, :with_pipeline, package: package) }

    it_behaves_like 'a working graphql query' do
      it_behaves_like 'matching the package details schema'
    end
  end
end

RSpec.shared_examples 'matching the package details schema' do
  it 'matches the JSON schema' do
    expect(package_details).to match_schema('graphql/packages/package_details')
  end
end

RSpec.shared_examples 'a package with files' do
  it 'has the right amount of files' do
    expect(package_files_response.length).to be(package.package_files.length)
  end

  it 'has the basic package files data' do
    expect(first_file_response).to include(
      'id' => global_id_of(first_file),
      'fileName' => first_file.file_name,
      'size' => first_file.size.to_s,
      'downloadPath' => first_file.download_path,
      'fileSha1' => first_file.file_sha1,
      'fileMd5' => first_file.file_md5,
      'fileSha256' => first_file.file_sha256
    )
  end

  context 'with package files pending destruction' do
    let_it_be(:package_file_pending_destruction) { create(:package_file, :pending_destruction, package: package) }

    let(:response_package_file_ids) { package_files_response.map { |pf| pf['id'] } }

    it 'does not return them' do
      expect(package.reload.package_files).to include(package_file_pending_destruction)

      expect(response_package_file_ids).not_to include(package_file_pending_destruction.to_global_id.to_s)
    end

    context 'with packages_installable_package_files disabled' do
      before(:context) do
        stub_feature_flags(packages_installable_package_files: false)
      end

      it 'returns them' do
        expect(package.reload.package_files).to include(package_file_pending_destruction)

        expect(response_package_file_ids).to include(package_file_pending_destruction.to_global_id.to_s)
      end
    end
  end
end

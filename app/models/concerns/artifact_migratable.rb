# Adapter class to unify the interface between mounted uploaders and the
# Ci::Artifact model
# Meant to be prepended so the interface can stay the same
module ArtifactMigratable
  def artifacts_file
    job_archive&.file || legacy_artifacts_file
  end

  def artifacts_file?
    job_archive&.file? || legacy_artifacts_file?
  end

  def artifacts_metadata
    job_metadata&.file || legacy_artifacts_metadata
  end

  def artifacts?
    !artifacts_expired? && artifacts_file.exists?
  end

  def artifacts_metadata?
    artifacts? && artifacts_metadata.exists?
  end

  def artifacts_file_changed?
    job_archive&.file_changed? || attribute_changed?(:artifacts_file)
  end

  def remove_artifacts_file!
    if job_archive
      job_archive.destroy
    else
      remove_legacy_artifacts_file!
    end
  end

  def remove_artifacts_metadata!
    if job_metadata
      job_metadata.destroy
    else
      remove_legacy_artifacts_metadata!
    end
  end

  def artifacts_size
    read_attribute(:artifacts_size).to_i +
      job_archive&.size.to_i + job_metadata&.size.to_i
  end
end

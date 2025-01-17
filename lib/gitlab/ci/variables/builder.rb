# frozen_string_literal: true

module Gitlab
  module Ci
    module Variables
      class Builder
        include ::Gitlab::Utils::StrongMemoize

        def initialize(pipeline)
          @pipeline = pipeline
        end

        def scoped_variables(job, environment:, dependencies:)
          Gitlab::Ci::Variables::Collection.new.tap do |variables|
            variables.concat(predefined_variables(job))

            next variables unless pipeline.use_variables_builder_definitions?

            variables.concat(project.predefined_variables)
            variables.concat(pipeline.predefined_variables)
            variables.concat(job.runner.predefined_variables) if job.runnable? && job.runner
            variables.concat(kubernetes_variables(job))
            variables.concat(deployment_variables(environment: environment, job: job))
            variables.concat(job.yaml_variables)
            variables.concat(user_variables(job.user))
            variables.concat(job.dependency_variables) if dependencies
            variables.concat(secret_instance_variables(ref: job.git_ref))
            variables.concat(secret_group_variables(environment: environment, ref: job.git_ref))
            variables.concat(secret_project_variables(environment: environment, ref: job.git_ref))
            variables.concat(job.trigger_request.user_variables) if job.trigger_request
            variables.concat(pipeline.variables)
            variables.concat(pipeline.pipeline_schedule.job_variables) if pipeline.pipeline_schedule
          end
        end

        def kubernetes_variables(job)
          ::Gitlab::Ci::Variables::Collection.new.tap do |collection|
            # Should get merged with the cluster kubeconfig in deployment_variables, see
            # https://gitlab.com/gitlab-org/gitlab/-/issues/335089
            template = ::Ci::GenerateKubeconfigService.new(job).execute

            if template.valid?
              collection.append(key: 'KUBECONFIG', value: template.to_yaml, public: false, file: true)
            end
          end
        end

        def deployment_variables(environment:, job:)
          return [] unless environment

          project.deployment_variables(
            environment: environment,
            kubernetes_namespace: job.expanded_kubernetes_namespace
          )
        end

        def user_variables(user)
          Gitlab::Ci::Variables::Collection.new.tap do |variables|
            break variables if user.blank?

            variables.append(key: 'GITLAB_USER_ID', value: user.id.to_s)
            variables.append(key: 'GITLAB_USER_EMAIL', value: user.email)
            variables.append(key: 'GITLAB_USER_LOGIN', value: user.username)
            variables.append(key: 'GITLAB_USER_NAME', value: user.name)
          end
        end

        def secret_instance_variables(ref:)
          project.ci_instance_variables_for(ref: ref)
        end

        def secret_group_variables(environment:, ref:)
          return [] unless project.group

          project.group.ci_variables_for(ref, project, environment: environment)
        end

        def secret_project_variables(environment:, ref:)
          project.ci_variables_for(ref: ref, environment: environment)
        end

        private

        attr_reader :pipeline
        delegate :project, to: :pipeline

        def predefined_variables(job)
          Gitlab::Ci::Variables::Collection.new.tap do |variables|
            variables.append(key: 'CI_JOB_NAME', value: job.name)
            variables.append(key: 'CI_JOB_STAGE', value: job.stage)
            variables.append(key: 'CI_JOB_MANUAL', value: 'true') if job.action?
            variables.append(key: 'CI_PIPELINE_TRIGGERED', value: 'true') if job.trigger_request

            variables.append(key: 'CI_NODE_INDEX', value: job.options[:instance].to_s) if job.options&.include?(:instance)
            variables.append(key: 'CI_NODE_TOTAL', value: ci_node_total_value(job).to_s)

            # legacy variables
            variables.append(key: 'CI_BUILD_NAME', value: job.name)
            variables.append(key: 'CI_BUILD_STAGE', value: job.stage)
            variables.append(key: 'CI_BUILD_TRIGGERED', value: 'true') if job.trigger_request
            variables.append(key: 'CI_BUILD_MANUAL', value: 'true') if job.action?
          end
        end

        def ci_node_total_value(job)
          parallel = job.options&.dig(:parallel)
          parallel = parallel.dig(:total) if parallel.is_a?(Hash)
          parallel || 1
        end
      end
    end
  end
end

# frozen_string_literal: true

module AlertManagement
  module Alerts
    class UpdateService < ::BaseProjectService
      include Gitlab::Utils::StrongMemoize

      # @param alert [AlertManagement::Alert]
      # @param current_user [User]
      # @param params [Hash] Attributes of the alert
      def initialize(alert, current_user, params)
        @alert = alert
        @param_errors = []
        @status = params.delete(:status)
        @status_change_reason = params.delete(:status_change_reason)

        super(project: alert.project, current_user: current_user, params: params)
      end

      def execute
        return error_no_permissions unless allowed?

        filter_params
        return error_invalid_params if param_errors.any?

        # Save old assignees for system notes
        old_assignees = alert.assignees.to_a

        if alert.update(params)
          handle_changes(old_assignees: old_assignees)

          success
        else
          error(alert.errors.full_messages.to_sentence)
        end
      end

      private

      attr_reader :alert, :param_errors, :status, :status_change_reason

      def allowed?
        current_user&.can?(:update_alert_management_alert, alert)
      end

      def todo_service
        strong_memoize(:todo_service) do
          TodoService.new
        end
      end

      def success
        ServiceResponse.success(payload: { alert: alert })
      end

      def error(message)
        ServiceResponse.error(payload: { alert: alert }, message: message)
      end

      def error_no_permissions
        error(_('You have no permissions'))
      end

      def error_invalid_params
        error(param_errors.to_sentence)
      end

      def add_param_error(message)
        param_errors << message
      end

      def param_errors?
        params.empty? && status.blank?
      end

      def filter_params
        param_errors << _('Please provide attributes to update') if param_errors?

        filter_status
        filter_assignees
        filter_duplicate
      end

      def handle_changes(old_assignees:)
        handle_assignement(old_assignees) if params[:assignees]
        handle_status_change if params[:status_event]
      end

      # ----- Assignee-related behavior ------
      def filter_assignees
        return if params[:assignees].nil?

        # Always take first assignee while multiple are not currently supported
        params[:assignees] = Array(params[:assignees].first)

        param_errors << _('Assignee has no permissions') if unauthorized_assignees?
      end

      def unauthorized_assignees?
        params[:assignees]&.any? { |user| !user.can?(:read_alert_management_alert, alert) }
      end

      def handle_assignement(old_assignees)
        assign_todo(old_assignees)
        add_assignee_system_note(old_assignees)
      end

      def assign_todo(old_assignees)
        todo_service.reassigned_assignable(alert, current_user, old_assignees)
      end

      def add_assignee_system_note(old_assignees)
        SystemNoteService.change_issuable_assignees(alert, project, current_user, old_assignees)
      end

      # ------ Status-related behavior -------
      def filter_status
        return unless status

        status_event = alert.status_event_for(status)

        unless status_event
          param_errors << _('Invalid status')
          return
        end

        params[:status_event] = status_event
      end

      def handle_status_change
        add_status_change_system_note
        resolve_todos if alert.resolved?
        sync_to_incident if should_sync_to_incident?
      end

      def add_status_change_system_note
        SystemNoteService.change_alert_status(alert, current_user, status_change_reason)
      end

      def resolve_todos
        todo_service.resolve_todos_for_target(alert, current_user)
      end

      def sync_to_incident
        ::Issues::UpdateService.new(
          project: project,
          current_user: current_user,
          params: {
            escalation_status: {
              status: status,
              status_change_reason: " by changing the status of #{alert.to_reference(project)}"
            }
          }
        ).execute(alert.issue)
      end

      def should_sync_to_incident?
        Feature.enabled?(:incident_escalations, project) &&
          alert.issue &&
          alert.issue.supports_escalation? &&
          alert.issue.escalation_status &&
          alert.issue.escalation_status.status != alert.status
      end

      def filter_duplicate
        # Only need to check if changing to an open status
        return unless params[:status_event] && AlertManagement::Alert.open_status?(status)

        param_errors << unresolved_alert_error if duplicate_alert?
      end

      def duplicate_alert?
        return if alert.fingerprint.blank?

        open_alerts.any? && open_alerts.exclude?(alert)
      end

      def open_alerts
        strong_memoize(:open_alerts) do
          AlertManagement::Alert.for_fingerprint(project, alert.fingerprint).open
        end
      end

      def unresolved_alert_error
        _('An %{link_start}alert%{link_end} with the same fingerprint is already open. ' \
          'To change the status of this alert, resolve the linked alert.'
         ) % open_alert_url_params
      end

      def open_alert_url_params
        open_alert = open_alerts.first
        alert_path = Gitlab::Routing.url_helpers.details_project_alert_management_path(project, open_alert)

        {
          link_start: '<a href="%{url}">'.html_safe % { url: alert_path },
          link_end: '</a>'.html_safe
        }
      end
    end
  end
end

AlertManagement::Alerts::UpdateService.prepend_mod

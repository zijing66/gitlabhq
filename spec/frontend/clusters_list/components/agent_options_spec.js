import { GlDropdown, GlDropdownItem, GlModal, GlFormInput } from '@gitlab/ui';
import Vue, { nextTick } from 'vue';
import VueApollo from 'vue-apollo';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import { ENTER_KEY } from '~/lib/utils/keys';
import getAgentsQuery from '~/clusters_list/graphql/queries/get_agents.query.graphql';
import deleteAgentMutation from '~/clusters_list/graphql/mutations/delete_agent.mutation.graphql';
import createMockApollo from 'helpers/mock_apollo_helper';
import waitForPromises from 'helpers/wait_for_promises';
import AgentOptions from '~/clusters_list/components/agent_options.vue';
import { MAX_LIST_COUNT } from '~/clusters_list/constants';
import { getAgentResponse, mockDeleteResponse, mockErrorDeleteResponse } from '../mocks/apollo';

Vue.use(VueApollo);

const projectPath = 'path/to/project';
const defaultBranchName = 'default';
const maxAgents = MAX_LIST_COUNT;
const agent = {
  id: 'agent-id',
  name: 'agent-name',
  webPath: 'agent-webPath',
};

describe('AgentOptions', () => {
  let wrapper;
  let toast;
  let apolloProvider;
  let deleteResponse;

  const findModal = () => wrapper.findComponent(GlModal);
  const findDropdown = () => wrapper.findComponent(GlDropdown);
  const findDeleteBtn = () => wrapper.findComponent(GlDropdownItem);
  const findInput = () => wrapper.findComponent(GlFormInput);
  const findPrimaryAction = () => findModal().props('actionPrimary');
  const findPrimaryActionAttributes = (attr) => findPrimaryAction().attributes[0][attr];

  const createMockApolloProvider = ({ mutationResponse }) => {
    deleteResponse = jest.fn().mockResolvedValue(mutationResponse);

    return createMockApollo([[deleteAgentMutation, deleteResponse]]);
  };

  const writeQuery = () => {
    apolloProvider.clients.defaultClient.cache.writeQuery({
      query: getAgentsQuery,
      variables: {
        projectPath,
        defaultBranchName,
        first: maxAgents,
        last: null,
      },
      data: getAgentResponse.data,
    });
  };

  const createWrapper = async ({ mutationResponse = mockDeleteResponse } = {}) => {
    apolloProvider = createMockApolloProvider({ mutationResponse });
    const provide = {
      projectPath,
    };
    const propsData = {
      defaultBranchName,
      maxAgents,
      agent,
    };

    toast = jest.fn();

    wrapper = shallowMountExtended(AgentOptions, {
      apolloProvider,
      provide,
      propsData,
      mocks: { $toast: { show: toast } },
      stubs: { GlModal },
    });
    wrapper.vm.$refs.modal.hide = jest.fn();

    writeQuery();
    await nextTick();
  };

  const submitAgentToDelete = async () => {
    findDeleteBtn().vm.$emit('click');
    findInput().vm.$emit('input', agent.name);
    await findModal().vm.$emit('primary');
    await waitForPromises();
  };

  beforeEach(() => {
    return createWrapper({});
  });

  afterEach(() => {
    wrapper.destroy();
    apolloProvider = null;
    deleteResponse = null;
    toast = null;
  });

  describe('delete agent action', () => {
    it('displays a delete button', () => {
      expect(findDeleteBtn().text()).toBe('Delete agent');
    });

    describe('when clicking the delete button', () => {
      beforeEach(() => {
        findDeleteBtn().vm.$emit('click');
      });

      it('displays a delete confirmation modal', () => {
        expect(findModal().isVisible()).toBe(true);
      });
    });

    describe.each`
      condition                                   | agentName       | isDisabled | mutationCalled
      ${'the input with agent name is missing'}   | ${''}           | ${true}    | ${false}
      ${'the input with agent name is incorrect'} | ${'wrong-name'} | ${true}    | ${false}
      ${'the input with agent name is correct'}   | ${agent.name}   | ${false}   | ${true}
    `('when $condition', ({ agentName, isDisabled, mutationCalled }) => {
      beforeEach(() => {
        findDeleteBtn().vm.$emit('click');
        findInput().vm.$emit('input', agentName);
      });

      it(`${isDisabled ? 'disables' : 'enables'} the modal primary button`, () => {
        expect(findPrimaryActionAttributes('disabled')).toBe(isDisabled);
      });

      describe('when user clicks the modal primary button', () => {
        beforeEach(async () => {
          await findModal().vm.$emit('primary');
        });

        if (mutationCalled) {
          it('calls the delete mutation', () => {
            expect(deleteResponse).toHaveBeenCalledWith({ input: { id: agent.id } });
          });
        } else {
          it("doesn't call the delete mutation", () => {
            expect(deleteResponse).not.toHaveBeenCalled();
          });
        }
      });

      describe('when user presses the enter button', () => {
        beforeEach(async () => {
          await findInput().vm.$emit('keydown', new KeyboardEvent({ key: ENTER_KEY }));
        });

        if (mutationCalled) {
          it('calls the delete mutation', () => {
            expect(deleteResponse).toHaveBeenCalledWith({ input: { id: agent.id } });
          });
        } else {
          it("doesn't call the delete mutation", () => {
            expect(deleteResponse).not.toHaveBeenCalled();
          });
        }
      });
    });

    describe('when agent was deleted successfully', () => {
      beforeEach(async () => {
        await submitAgentToDelete();
      });

      it('calls the toast action', () => {
        expect(toast).toHaveBeenCalledWith(`${agent.name} successfully deleted`);
      });
    });
  });

  describe('when getting an error deleting agent', () => {
    beforeEach(async () => {
      await createWrapper({ mutationResponse: mockErrorDeleteResponse });
      await submitAgentToDelete();
    });

    it('displays the error message', () => {
      expect(toast).toHaveBeenCalledWith('could not delete agent');
    });
  });

  describe('when the delete modal was closed', () => {
    beforeEach(async () => {
      const loadingResponse = new Promise(() => {});
      await createWrapper({ mutationResponse: loadingResponse });

      await submitAgentToDelete();
    });

    it('reenables the options dropdown', async () => {
      expect(findPrimaryActionAttributes('loading')).toBe(true);
      expect(findDropdown().attributes('disabled')).toBe('true');

      await findModal().vm.$emit('hide');

      expect(findPrimaryActionAttributes('loading')).toBe(false);
      expect(findDropdown().attributes('disabled')).toBeUndefined();
    });

    it('clears the agent name input', async () => {
      expect(findInput().attributes('value')).toBe(agent.name);

      await findModal().vm.$emit('hide');

      expect(findInput().attributes('value')).toBeUndefined();
    });
  });
});

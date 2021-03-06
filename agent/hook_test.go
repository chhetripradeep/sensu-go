package agent

import (
	"path/filepath"
	"testing"

	"github.com/sensu/sensu-go/testing/testutil"
	"github.com/sensu/sensu-go/transport"
	"github.com/sensu/sensu-go/types"
	"github.com/stretchr/testify/assert"
)

func TestExecuteHook(t *testing.T) {
	assert := assert.New(t)

	hookConfig := types.FixtureHookConfig("hook")
	hookConfig.Stdin = true

	config := FixtureConfig()
	agent := NewAgent(config)
	ch := make(chan *transport.Message, 1)
	agent.sendq = ch

	truePath := testutil.CommandPath(filepath.Join(toolsDir, "true"))
	hookConfig.Command = truePath

	hook := agent.executeHook(hookConfig)

	assert.NotZero(hook.Executed)
	assert.Equal(hook.Status, int32(0))
	assert.Equal(hook.Output, "")

	hookConfig.Command = "printf hello"

	hook = agent.executeHook(hookConfig)

	assert.NotZero(hook.Executed)
	assert.Equal(hook.Status, int32(0))
	assert.Equal(hook.Output, "hello")
}

func TestPrepareHook(t *testing.T) {
	assert := assert.New(t)

	config := FixtureConfig()
	agent := NewAgent(config)

	// nil hook
	assert.False(agent.prepareHook(nil))

	// Invalid hook
	hook := types.FixtureHookConfig("hook")
	hook.Command = ""
	assert.False(agent.prepareHook(hook))

	// Valid check
	hook.Command = "{{ .ID }}"
	assert.True(agent.prepareHook(hook))
}

func TestHookInList(t *testing.T) {
	assert := assert.New(t)
	hook1 := types.FixtureHook("hook1")
	hook2 := types.FixtureHook("hook2")

	testCases := []struct {
		name     string
		hookName string
		hookList []*types.Hook
		expected bool
	}{
		{
			name:     "Empty list",
			hookName: "hook1",
			hookList: []*types.Hook{},
			expected: false,
		},
		{
			name:     "Hook in populated list",
			hookName: "hook1",
			hookList: []*types.Hook{hook2, hook1},
			expected: true,
		},
		{
			name:     "Hook not in populated list",
			hookName: "hook1",
			hookList: []*types.Hook{hook2, hook2},
			expected: false,
		},
		{
			name:     "No hook name provided",
			hookName: "",
			hookList: []*types.Hook{hook1, hook2},
			expected: false,
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			in := hookInList(tc.hookName, tc.hookList)
			assert.Equal(tc.expected, in)
		})
	}
}

local lifecycle = require('config.git.lifecycle')
local logged_messages = {}
local original_diffview_global = rawget(_G, 'DiffviewGlobal')
_G.DiffviewGlobal = {
  logger = {
    info = function(_, message)
      logged_messages[#logged_messages + 1] = message
    end,
    warn = function(_, message)
      logged_messages[#logged_messages + 1] = message
    end,
  },
}

local view = {}
local attached = lifecycle.attach(view, 'symbol')
assert(attached.phase == 'mounting', 'Git lifecycle did not start in mounting')
assert(
  lifecycle.set_activity(view, 'head', 'current branch')
    and lifecycle.set_activity(view, 'history', 'symbol matches')
    and vim.deep_equal(lifecycle.activity_labels(view), {
      'current branch',
      'symbol matches',
    })
    and lifecycle.clear_activity(view, 'head')
    and vim.deep_equal(lifecycle.activity_labels(view), { 'symbol matches' }),
  'Git lifecycle did not retain deterministic asynchronous activity status'
)
lifecycle.clear_activity(view, 'history')
assert(lifecycle.transition(view, 'listing', 'test open'), 'Git lifecycle rejected listing')
local generation = lifecycle.generation(view)
local render_sequence = lifecycle.begin_render(view, 'newest-commit', 'sample.lua', 'initial')
assert(lifecycle.mark_list_ready(view, 2), 'Git lifecycle did not accept the settled list')
assert(
  lifecycle.complete_render(view, render_sequence, 'newest-commit', 'sample.lua', true),
  'Git lifecycle rejected its current render callback'
)
assert(not lifecycle.try_ready(view, 'before enrichment'), 'Git lifecycle became ready too early')
assert(
  lifecycle.mark_enrichment_ready(view, 'newest-commit', 'sample.lua')
    and lifecycle.try_ready(view, 'newest match rendered')
    and lifecycle.is_ready(view)
    and lifecycle.render_is_ready(view),
  'Git lifecycle did not become ready at the complete render boundary'
)
assert(lifecycle.begin_anchor(view, 'selected commit'), 'Ready Git lifecycle rejected anchor start')
local anchor_render = lifecycle.begin_render(view, 'anchor-commit', 'sample.lua', 'anchor render')
assert(anchor_render, 'Git lifecycle did not begin its anchor render')
assert(lifecycle.cancel_anchor(view, 'dirty worktree'), 'Git lifecycle did not recover from anchor refusal')
assert(
  lifecycle.render_is_ready(view),
  'Cancelled anchor render did not restore the preceding stable target'
)

local later_render = lifecycle.begin_render(view, 'older-commit', 'sample.lua', 'user selection')
assert(not lifecycle.request_return(view, 'during file render'), 'Git lifecycle exited mid-render')
assert(
  lifecycle.complete_render(view, later_render, 'older-commit', 'sample.lua', true)
    and lifecycle.try_ready(view, 'older match rendered')
    and lifecycle.phase(view) == 'return_wait',
  'Pending exit did not settle at a render-complete wait boundary'
)
assert(lifecycle.request_return(view, 'second deliberate request'), 'Ready exit request was rejected')
assert(lifecycle.phase(view) == 'returning', 'Git lifecycle did not enter returning')
assert(lifecycle.mark_closing(view, 'editor rendered'), 'Git lifecycle did not enter closing')
assert(lifecycle.mark_aligning(view, 'Diffview disposed'), 'Git lifecycle did not enter aligning')
assert(lifecycle.mark_disposed(view, 'Diffview disposed'), 'Git lifecycle did not enter disposed')
assert(
  not lifecycle.callback_is_current(view, generation, 'late enrichment', 'after disposal'),
  'Disposed Git lifecycle accepted a stale callback'
)
assert(
  table.concat(logged_messages, '\n'):match('%[Git lifecycle g=')
    and table.concat(logged_messages, '\n'):match('discarded stale'),
  'Git lifecycle did not emit structured transition and callback logs'
)

local initializing_view = {}
lifecycle.attach(initializing_view, 'repository')
assert(lifecycle.transition(initializing_view, 'listing', 'initial list'))
assert(
  lifecycle.request_return(initializing_view, 'quit during initialization')
    and lifecycle.phase(initializing_view) == 'returning',
  'Git lifecycle did not accept cancellation during its initial render'
)
assert(lifecycle.mark_closing(initializing_view, 'initial render cancelled'))
assert(lifecycle.mark_disposed(initializing_view, 'initial view disposed'))

local failed_view = {}
lifecycle.attach(failed_view, 'repository')
assert(lifecycle.transition(failed_view, 'listing', 'failed history list'))
assert(
  lifecycle.mark_failed(failed_view, 'history list timeout')
    and lifecycle.phase(failed_view) == 'failed',
  'Git lifecycle did not enter an explicit terminal failure phase'
)
assert(
  lifecycle.request_return(failed_view, 'quit after timeout'),
  'A failed Git lifecycle trapped the user instead of allowing exit'
)
assert(lifecycle.mark_closing(failed_view, 'failed view closing'))
assert(lifecycle.mark_disposed(failed_view, 'failed view disposed'))

local idle_view = {}
lifecycle.attach(idle_view, 'repository')
assert(lifecycle.transition(idle_view, 'listing', 'idle history list'))
assert(
  lifecycle.mark_idle_ready(idle_view, 'waiting for explicit file selection')
    and lifecycle.is_ready(idle_view)
    and lifecycle.render_is_ready(idle_view),
  'An intentionally empty Git history did not reach a stable ready boundary'
)
local explicit_render = lifecycle.begin_render(
  idle_view,
  'selected-commit',
  'selected.lua',
  'explicit file open'
)
assert(
  explicit_render
    and not lifecycle.render_is_ready(idle_view)
    and lifecycle.complete_render(
      idle_view,
      explicit_render,
      'selected-commit',
      'selected.lua',
      true
    )
    and lifecycle.try_ready(idle_view, 'explicit file rendered'),
  'Explicit file selection did not replace the stable empty render boundary'
)

_G.DiffviewGlobal = original_diffview_global

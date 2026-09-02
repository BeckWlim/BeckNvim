local events = require('config.git.events')

local M = {}

local generation_counter = 0

local allowed_transitions = {
  mounting = { listing = true, closing = true, failed = true },
  listing = { enriching = true, rendering = true, ready = true, closing = true, failed = true },
  enriching = { rendering = true, ready = true, closing = true, failed = true },
  rendering = { rendering = true, ready = true, return_wait = true, closing = true, failed = true },
  ready = { rendering = true, returning = true, anchoring = true, closing = true, failed = true },
  return_wait = { rendering = true, returning = true, anchoring = true, closing = true, failed = true },
  anchoring = { rendering = true, ready = true, closing = true, failed = true },
  returning = { closing = true, failed = true },
  closing = { aligning = true, disposed = true, failed = true },
  aligning = { disposed = true, failed = true },
  failed = { closing = true, disposed = true },
  disposed = {},
}

local terminal_phases = {
  closing = true,
  disposed = true,
  failed = true,
}

local function lifecycle_state(view)
  return view and view.git_lifecycle or nil
end

local function elapsed_milliseconds(lifecycle)
  return (vim.uv.hrtime() - lifecycle.started_at_ns) / 1000000
end

local function log_message(lifecycle, event, outcome, detail, level)
  local diffview_global = rawget(_G, 'DiffviewGlobal')
  local logger = diffview_global and diffview_global.logger
  local log_method = logger and logger[level or 'info']
  if type(log_method) ~= 'function' then
    return
  end
  local detail_suffix = detail and detail ~= '' and ' · ' .. detail or ''
  local message = ('[Git lifecycle g=%d phase=%s +%.1fms] %s · %s%s'):format(
    lifecycle.generation,
    lifecycle.phase,
    elapsed_milliseconds(lifecycle),
    event,
    outcome,
    detail_suffix
  )
  pcall(log_method, logger, message)
end

local function target_matches(expected_target, rendered_target)
  return expected_target
    and rendered_target
    and expected_target.commit == rendered_target.commit
    and expected_target.path == rendered_target.path
end

function M.attach(view, kind)
  generation_counter = generation_counter + 1
  local scoped_history = kind == 'file' or kind == 'symbol'
  local lifecycle = {
    alignment_ready = false,
    enrichment_ready = not scoped_history,
    expected_target = nil,
    generation = generation_counter,
    initializing = true,
    kind = kind,
    list_ready = false,
    phase = 'mounting',
    render_sequence = 0,
    rendered_target = nil,
    return_requested = false,
    started_at_ns = vim.uv.hrtime(),
  }
  view.git_lifecycle = lifecycle
  log_message(lifecycle, 'attach', 'accepted', 'kind=' .. tostring(kind), 'info')
  events.emit('phase', {
    generation = lifecycle.generation,
    kind = kind,
    phase = lifecycle.phase,
  })
  return lifecycle
end

function M.get(view)
  return lifecycle_state(view)
end

function M.generation(view)
  local lifecycle = lifecycle_state(view)
  return lifecycle and lifecycle.generation or nil
end

function M.phase(view)
  local lifecycle = lifecycle_state(view)
  return lifecycle and lifecycle.phase or nil
end

function M.is_current(view, generation)
  local lifecycle = lifecycle_state(view)
  return lifecycle
    and lifecycle.generation == generation
    and not terminal_phases[lifecycle.phase]
    or false
end

function M.log(view, event, outcome, detail, level)
  local lifecycle = lifecycle_state(view)
  if lifecycle then
    log_message(lifecycle, event, outcome, detail, level)
  end
end

function M.callback_is_current(view, generation, callback_name, detail)
  local accepted = M.is_current(view, generation)
  M.log(
    view,
    'callback ' .. callback_name,
    accepted and 'accepted' or 'discarded stale',
    detail,
    accepted and 'info' or 'warn'
  )
  return accepted
end

function M.transition(view, next_phase, event, detail)
  local lifecycle = lifecycle_state(view)
  if not lifecycle then
    return false
  end
  local previous_phase = lifecycle.phase
  if not (allowed_transitions[previous_phase] or {})[next_phase] then
    log_message(
      lifecycle,
      event,
      ('rejected transition %s→%s'):format(previous_phase, next_phase),
      detail,
      'warn'
    )
    return false
  end
  lifecycle.phase = next_phase
  log_message(
    lifecycle,
    event,
    ('transition %s→%s'):format(previous_phase, next_phase),
    detail,
    'info'
  )
  events.emit('phase', {
    detail = detail,
    event = event,
    generation = lifecycle.generation,
    kind = lifecycle.kind,
    phase = next_phase,
    previous_phase = previous_phase,
  })
  if next_phase == 'ready' or next_phase == 'return_wait' then
    events.emit('ready', {
      generation = lifecycle.generation,
      kind = lifecycle.kind,
      return_requested = lifecycle.return_requested,
    })
  elseif next_phase == 'returning' then
    events.emit('return_started', {
      generation = lifecycle.generation,
    })
  elseif next_phase == 'disposed' and lifecycle.return_requested then
    events.emit('return_finished', {
      generation = lifecycle.generation,
    })
  end
  return true
end

function M.mark_list_ready(view, entry_count)
  local lifecycle = lifecycle_state(view)
  if not lifecycle then
    return false
  end
  lifecycle.list_ready = true
  local detail = ('entries=%d'):format(entry_count)
  if lifecycle.enrichment_ready then
    if lifecycle.phase == 'listing' then
      M.transition(view, 'rendering', 'history list ready', detail)
    else
      M.log(view, 'history list ready', 'recorded', detail, 'info')
    end
  elseif lifecycle.phase == 'listing' then
    M.transition(view, 'enriching', 'history list ready', detail)
  else
    M.log(view, 'history list ready', 'recorded', detail, 'info')
  end
  return true
end

function M.mark_enrichment_ready(view, expected_commit, expected_path)
  local lifecycle = lifecycle_state(view)
  if not lifecycle then
    return false
  end
  lifecycle.enrichment_ready = true
  lifecycle.expected_target = expected_commit and expected_path and {
    commit = expected_commit,
    path = expected_path,
  } or lifecycle.expected_target
  M.log(
    view,
    'footer enrichment',
    'complete',
    ('target=%s:%s'):format(expected_commit or 'none', expected_path or 'none'),
    'info'
  )
  return true
end

function M.expect_target(view, commit_hash, file_path, reason)
  local lifecycle = lifecycle_state(view)
  if not lifecycle or not commit_hash or not file_path then
    return false
  end
  lifecycle.expected_target = {
    commit = commit_hash,
    path = file_path,
  }
  M.log(
    view,
    'render target',
    'expected',
    ('target=%s:%s reason=%s'):format(commit_hash, file_path, reason or 'unknown'),
    'info'
  )
  return true
end

function M.begin_render(view, commit_hash, file_path, reason)
  local lifecycle = lifecycle_state(view)
  if not lifecycle or terminal_phases[lifecycle.phase] then
    return
  end
  lifecycle.render_sequence = lifecycle.render_sequence + 1
  lifecycle.rendered_target = nil
  lifecycle.alignment_ready = false
  local render_target = {
    commit = commit_hash,
    path = file_path,
    sequence = lifecycle.render_sequence,
  }
  if lifecycle.initializing and not lifecycle.expected_target then
    lifecycle.expected_target = {
      commit = commit_hash,
      path = file_path,
    }
  end
  if not lifecycle.initializing then
    lifecycle.expected_target = {
      commit = commit_hash,
      path = file_path,
    }
  end
  if lifecycle.phase == 'ready' or lifecycle.phase == 'return_wait'
      or lifecycle.phase == 'anchoring' then
    M.transition(
      view,
      'rendering',
      'file render start',
      ('seq=%d target=%s:%s reason=%s'):format(
        render_target.sequence,
        commit_hash or 'none',
        file_path or 'none',
        reason or 'unknown'
      )
    )
  else
    M.log(
      view,
      'file render start',
      'recorded',
      ('seq=%d target=%s:%s reason=%s'):format(
        render_target.sequence,
        commit_hash or 'none',
        file_path or 'none',
        reason or 'unknown'
      ),
      'info'
    )
  end
  return render_target.sequence
end

function M.complete_render(view, render_sequence, commit_hash, file_path, aligned)
  local lifecycle = lifecycle_state(view)
  if not lifecycle or render_sequence ~= lifecycle.render_sequence then
    M.log(
      view,
      'file render complete',
      'discarded stale',
      ('seq=%s current=%s target=%s:%s'):format(
        tostring(render_sequence),
        lifecycle and tostring(lifecycle.render_sequence) or 'none',
        commit_hash or 'none',
        file_path or 'none'
      ),
      'warn'
    )
    return false
  end
  lifecycle.rendered_target = {
    commit = commit_hash,
    path = file_path,
    sequence = render_sequence,
  }
  lifecycle.alignment_ready = aligned
  M.log(
    view,
    'file render complete',
    aligned and 'aligned' or 'rendered without alignment',
    ('seq=%d target=%s:%s'):format(
      render_sequence,
      commit_hash or 'none',
      file_path or 'none'
    ),
    aligned and 'info' or 'warn'
  )
  return true
end

function M.try_ready(view, detail)
  local lifecycle = lifecycle_state(view)
  if not lifecycle
      or not lifecycle.list_ready
      or not lifecycle.enrichment_ready
      or not lifecycle.alignment_ready
      or not target_matches(lifecycle.expected_target, lifecycle.rendered_target) then
    if lifecycle then
      M.log(
        view,
        'readiness check',
        'waiting',
        ('list=%s enrich=%s align=%s expected=%s:%s rendered=%s:%s%s'):format(
          tostring(lifecycle.list_ready),
          tostring(lifecycle.enrichment_ready),
          tostring(lifecycle.alignment_ready),
          lifecycle.expected_target and lifecycle.expected_target.commit or 'none',
          lifecycle.expected_target and lifecycle.expected_target.path or 'none',
          lifecycle.rendered_target and lifecycle.rendered_target.commit or 'none',
          lifecycle.rendered_target and lifecycle.rendered_target.path or 'none',
          detail and ' · ' .. detail or ''
        ),
        'info'
      )
    end
    return false
  end
  lifecycle.initializing = false
  lifecycle.anchor_snapshot = nil
  local next_phase = lifecycle.return_requested and 'return_wait' or 'ready'
  if lifecycle.phase == next_phase then
    return true
  end
  return M.transition(view, next_phase, 'readiness check', detail)
end

function M.mark_empty_ready(view, detail)
  local lifecycle = lifecycle_state(view)
  if not lifecycle then
    return false
  end
  lifecycle.list_ready = true
  lifecycle.enrichment_ready = true
  lifecycle.alignment_ready = true
  lifecycle.expected_target = { commit = 'EMPTY', path = 'EMPTY' }
  lifecycle.rendered_target = { commit = 'EMPTY', path = 'EMPTY', sequence = 0 }
  return M.try_ready(view, detail or 'empty history')
end

function M.is_ready(view)
  local lifecycle = lifecycle_state(view)
  return lifecycle
    and (lifecycle.phase == 'ready' or lifecycle.phase == 'return_wait')
    or false
end

function M.render_is_ready(view)
  local lifecycle = lifecycle_state(view)
  return lifecycle
    and lifecycle.list_ready
    and lifecycle.enrichment_ready
    and lifecycle.alignment_ready
    and target_matches(lifecycle.expected_target, lifecycle.rendered_target)
    or false
end

function M.request_return(view, detail)
  local lifecycle = lifecycle_state(view)
  if not lifecycle then
    return false
  end
  lifecycle.return_requested = true
  if not M.is_ready(view) then
    M.log(view, 'exit request', 'waiting for ready render', detail, 'info')
    return false
  end
  return M.transition(view, 'returning', 'exit request', detail)
end

function M.begin_anchor(view, detail)
  local lifecycle = lifecycle_state(view)
  if not lifecycle or not M.is_ready(view) then
    M.log(view, 'anchor request', 'rejected before ready', detail, 'warn')
    return false
  end
  lifecycle.anchor_snapshot = {
    alignment_ready = lifecycle.alignment_ready,
    expected_target = lifecycle.expected_target and vim.deepcopy(lifecycle.expected_target) or nil,
    rendered_target = lifecycle.rendered_target and vim.deepcopy(lifecycle.rendered_target) or nil,
  }
  return M.transition(view, 'anchoring', 'anchor request', detail)
end

function M.cancel_anchor(view, detail)
  local lifecycle = lifecycle_state(view)
  if not lifecycle
      or (lifecycle.phase ~= 'anchoring' and lifecycle.phase ~= 'rendering') then
    return false
  end
  local anchor_snapshot = lifecycle.anchor_snapshot
  if anchor_snapshot then
    lifecycle.alignment_ready = anchor_snapshot.alignment_ready
    lifecycle.expected_target = anchor_snapshot.expected_target
    lifecycle.rendered_target = anchor_snapshot.rendered_target
  end
  lifecycle.anchor_snapshot = nil
  return M.transition(view, 'ready', 'anchor cancelled', detail)
end

function M.mark_closing(view, detail)
  local lifecycle = lifecycle_state(view)
  if not lifecycle then
    return false
  end
  if lifecycle.phase == 'closing' or lifecycle.phase == 'disposed' then
    return true
  end
  return M.transition(view, 'closing', 'view close', detail)
end

function M.mark_disposed(view, detail)
  local lifecycle = lifecycle_state(view)
  if not lifecycle then
    return false
  end
  return M.transition(view, 'disposed', 'view dispose', detail)
end

function M.mark_aligning(view, detail)
  local lifecycle = lifecycle_state(view)
  if not lifecycle then
    return false
  end
  return M.transition(view, 'aligning', 'editor alignment', detail)
end

return M

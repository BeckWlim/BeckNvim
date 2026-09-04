local reference = require('config.git.reference')
local repository = require('config.git.repository')

local direct_reference = reference.parse_record_url(
  'https://github.com/example/project/pull/42/files'
)
assert(
  direct_reference
    and direct_reference.kind == 'Pull request'
    and direct_reference.number == 42
    and direct_reference.remote.owner == 'example',
  'Git reference parser lost a direct pull-request URL'
)

local remote = reference.parse_remote_url('git@github.com:example/project.git')
assert(
  remote and remote.host == 'github.com' and remote.repository == 'project',
  'Git reference parser lost an SSH remote URL'
)

local remote_config_output = table.concat({
  'remote.upstream.url\ngit@github.com:upstream/project.git',
  'remote.origin.url\nhttps://github.com/example/project.git',
}, '\0') .. '\0'
local parsed_git_references = reference.parse_git_output(remote_config_output, '17')
assert(
  #parsed_git_references == 2
    and parsed_git_references[1].number == 17
    and parsed_git_references[1].remote.name == 'origin'
    and parsed_git_references[2].remote.name == 'upstream',
  'Git command output did not produce ordered downstream record references'
)

local original_repository_start = repository.start
local invoked_command
local invoked_root
local resolved_references
repository.start = function(command, root, callback)
  invoked_command = command
  invoked_root = root
  callback({ code = 0, stderr = '', stdout = remote_config_output })
  return function() end
end
reference.resolve_local('/work/example/../project', 17, function(record_references, resolution_error)
  assert(not resolution_error, resolution_error)
  resolved_references = record_references
end)
assert(
  vim.deep_equal(invoked_command, repository.commands.remote_urls())
    and invoked_root == '/work/project'
    and resolved_references
    and resolved_references[1].remote.owner == 'example',
  'Local path did not resolve through the bounded Git command into downstream references'
)
repository.start = original_repository_start

package buildkite

deny[msg] {
  step := input.steps[_]

  not step.timeout_in_minutes
  msg := sprintf("Step '%s' must define timeout_in_minutes", [step.label])
}

deny[msg] {
  step := input.steps[_]
  step.agents.queue == "default"
  msg := sprintf("Step '%s' must not use the default agent queue", [step.label])
}

deny[msg] {
  step := input.steps[_]
  step.image
  contains(step.image, ":latest")
  msg := sprintf("Step '%s' uses an unpinned image (%s)", [step.label, step.image])
}

deny[msg] {
  step := input.steps[_]
  step.retry
  not step.retry
  msg := sprintf("Step '%s' should define a retry policy", [step.label])
}

deny[msg] {
  step := input.steps[_]
  step.plugins
  plugin := step.plugins[_]
  startswith(object.keys(plugin)[0], "docker#")
  msg := sprintf("Docker plugin usage is forbidden in step '%s'", [step.label])
}

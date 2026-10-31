# FPGA Codex Rules

- Default to a low-cost agent for bounded RTL tasks and Use RTL Design Skill.
- Use a stronger agent for CDC, timing, architecture,
  complex arithmetic and ambiguous specifications.
- Do not spawn subagents for trivial single-file edits.
- Limit parallel agents to independent tasks.
- Never allow two agents to edit the same file concurrently.
- Read only relevant RTL files and their dependencies.
- Do not scan generated Vivado output directories.
- Do not read waveforms, logs or netlists in full.
- Preserve existing interfaces unless explicitly requested.
- Every RTL change must include focused verification.
- Prefer targeted tests over full project builds.
- Return only changed files, verification results,
  unresolved risks and a short summary.
- Escalate to a stronger model after two failed
  implementation or debugging attempts.
- Use Xilinx Ross MCP when need to deal with FPGA hardware.
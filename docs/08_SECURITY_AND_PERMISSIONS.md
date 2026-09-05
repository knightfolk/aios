# Security, Privacy, Permissions, and Side Effects

## Principle

Containment and deterministic enforcement are the security boundary. Model judgment may inform but cannot authorize itself.

## Capability classes

### Observe
Read selected files, inspect repo status, view screen/app state, read approved sources.

### Modify workspace
Edit files within task scope, create worktree/checkpoints, run approved build/test commands.

### Operate computer
Accessibility control, browser/app interactions, keyboard/mouse events.

### External consequence
Send, publish, deploy, purchase, delete remote data, change account state, submit forms, or otherwise affect the outside world.

## Goal-level grants

A Goal may authorize a bounded working envelope:
- filesystem roots,
- approved commands/tool classes,
- network hosts/services,
- cloud model policy,
- spending cap,
- computer-control apps,
- retention policy.

## Action-level approval

Required for consequential operations outside the current envelope. Approval must identify the actual target/payload/version where relevant.

## Local Only

Local Only must block unapproved outbound paths, including:
- cloud inference,
- remote tools/plugins,
- browser/network access,
- shell networking,
- telemetry,
- remote workers,
- derived data uploads.

A badge is not sufficient; enforce at broker/network boundaries.

## Credential broker

Secrets should live in Keychain/brokered services. Prefer typed operations such as `repository.push(branch)` over giving models raw tokens.

Never place credentials in model context. Avoid placing credentials in sandbox environment variables unless unavoidable and explicitly authorized.

## Untrusted input

Treat all of the following as untrusted:
- repository files,
- documents,
- web pages,
- screenshots,
- emails/messages,
- model output,
- tool output,
- MCP servers,
- Skills and scripts.

Untrusted input cannot redefine user intent, security policy, or permission scope.

## Action transaction lifecycle

```text
Prepare
→ Validate current state/preconditions
→ Authorize
→ Execute
→ Observe
→ Reconcile
→ Record outcome
```

Non-idempotent and `UNKNOWN` outcomes require reconciliation before retry.

## Chloe computer-control lease

The real user desktop has one exclusive automation owner at a time.

Lease includes:
- Project/Task owner,
- target applications,
- purpose,
- allowed action classes,
- expiry.

User interaction immediately outranks automation and invalidates pending focus/screen assumptions. Chloe must observe again before continuing.

Preferred interaction order:
1. Native API/tool.
2. MCP/service API.
3. Accessibility element tree.
4. Browser DOM automation.
5. Screenshot/pixel computer-use model.

## Shadow Mode

Chloe may propose/highlight intended actions without executing them. Useful for training, debugging, safety review, and onboarding.

## Emergency Stop

Must be local, deterministic, always responsive, and independent of LLM availability.

Emergency Stop prevents new computer/external side effects, cancels or freezes controllable pending actions, and records the interruption.

Distinguish:
- Stop speaking
- Pause work at safe checkpoint
- Emergency Stop

## Extensions

Executable Skills/plugins run out of process/sandboxed where practical, declare capabilities, use pinned versions, and require reapproval when permission scope expands.
